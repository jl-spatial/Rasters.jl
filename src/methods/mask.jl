"""
    mask(A::AbstractRaster; to, missingval=missingval(A))
    mask(x; to, order=(XDim, YDim))

Return a new array with values of `A` masked by the missing values of `to`,
or by when more than 50% outside `to`, if it is a polygon.

# Arguments

- `x`: a `Raster` or `RasterStack`

# Keywords

- `to`: another `AbstractRaster`, a `AbstractVector` of `Tuple` points,
    or any GeoInterface.jl `AbstractGeometry`. The coordinate reference system
    of the point must match `crs(A)`.
- `order`: the order of `Dimension`s in the points. Defaults to `(XDim, YDim)`.
- `missingval`: the order of dimensions in the points. Defaults to `(XDim, YDim)`.

In future this method will accept more point types.

# Example

Mask an unmasked AWAP layer with a masked WorldClim layer,
by first resampling the mask.

```jldoctest
using Rasters, Plots, Dates

# Load and plot the file
awap = read(Raster(AWAP, :tmax; date=DateTime(2001, 1, 1)))
a = plot(awap; clims=(10, 45))

# Create a mask my resampling a worldclim file
wc = Raster(WorldClim{Climate}, :prec; month=1)
wc_mask = resample(wc; to=awap)

# Mask
awap_masked = mask(awap; to=wc_mask)
b = plot(awap_masked; clims=(10, 45))

savefig(a, "build/mask_example_before.png")
savefig(b, "build/mask_example_after.png")
# output

```

### Before `mask`:

![before mask](mask_example_before.png)

### After `mask`:

![after mask](mask_example_after.png)

$EXPERIMENTAL
"""
function mask end
mask(xs::AbstractRasterSeries; kw...) = map(x -> mask(x; kw...), xs)
mask(xs::AbstractRasterStack; to, kw...) = _mask(xs, to; kw...)
mask(A::AbstractRaster; to, kw...) = _mask(A, to; kw...)

_mask(xs::RasterStack, to::AbstractArray; kw...) = map(x -> mask(x; to, kw...),  xs)
function _mask(st::RasterStack, to::AbstractVector;
    order=dims(st, (XDim, YDim)), kw...
)
    # Mask it with the polygon
    B = _poly_mask(first(st), to; order, kw...)
    # Run array masking to=B over all layers
    return map(x -> _mask(x, B; kw...),  st)
end
function _mask(A::RasterStackOrArray, poly::GI.AbstractGeometry; kw...)
    _mask(A, GI.coordinates(poly); kw...)
end
function _mask(A::AbstractRaster, poly::AbstractVector; order=(X, Y),kw...)
    # Mask it with the polygon
    B = _poly_mask(A, poly; order, kw...)
    # Then apply it to A. This is much faster when
    # A has additional dimensions to broadcast over.
    return _mask(A, B; kw...)
end
function _mask(A::AbstractRaster, to::AbstractArray; missingval=_missingval_or_missing(A), kw...)
    return mask!(read(replace_missing(A, missingval)); to, missingval)
end

function _bool_template(A, order)
    template = if length(otherdims(A, order)) > 0
        # There are more dimensions than the order of the points have,
        # so we can just broadcast over the additional dimensions later.
        # So we take a view with ones in the other dimensions.
        otherdim_ones = map(otherdims(A, order)) do d
            DD.basetypeof(d)(1)
        end
        view(A, otherdim_ones...)
    else
        A # There are no other dims, use as-is
    end
    return boolmask(BitArray, template)
end

"""
    mask!(A; to, missingval=missing, order=(XDim, YDim))

Mask `A` by the missing values of `to`, or by values outside `to` if i is a polygon.

If `to` is a polygon, creates a new array where points falling outside the polygon
have been replaced by `missingval(A)`.

Return a new array with values of `A` masked by the missing values of `to`,
or by a polygon.

# Arguments

- `x`: a `Raster` or `RasterStack`.

# Keywords

- `to`: another `AbstractRaster`, a `AbstractVector` of `Tuple` points,
    or any GeoInterface.jl `AbstractGeometry`. The coordinate reference system
    of the point must match `crs(A)`.
- `order`: the order of `Dimension`s in the points. Defaults to `(XDim, YDim)`.
- `missingval`: the order of dimensions in the points. Defaults to `(XDim, YDim)`.

# Example

Mask an unmasked AWAP layer with a masked WorldClim layer,
by first resampling the mask to match the size and projection.

```jldoctest
using Rasters, Plots, Dates

# Load and plot the file
awap = read(RasterStack(AWAP, (:tmin, :tmax); date=DateTime(2001, 1, 1)))
a = plot(awap; clims=(10, 45))

# Create a mask my resampling a worldclim file
wc = Raster(WorldClim{Climate}, :prec; month=1)
wc_mask = resample(wc; to=awap)

# Mask
mask!(awap; to=wc_mask)
b = plot(awap; clims=(10, 45))

savefig(a, "build/mask_bang_example_before.png")
savefig(b, "build/mask_bang_example_after.png")
# output
```

### Before `mask!`:

![before mask!](mask_bang_example_before.png)

### After `mask!`:

![after mask!](mask_bang_example_after.png)

$EXPERIMENTAL
"""
mask!(xs::AbstractRasterSeries, args...; kw...) = map(x -> mask!(x, args...; kw...),  xs)
mask!(xs::AbstractRasterStack; to, kw...) = _mask!(xs, to; kw...)
mask!(A::AbstractRaster; to, kw...) = _mask!(A, to; kw...)

# Polygon mask
function _mask!(A::AbstractRasterStack, poly::GI.AbstractGeometry; kw...)
    _mask!(A, GI.coordinates(poly))
end
# Coordinates mask
function _mask!(st::RasterStack, to::AbstractVector; order=(X, Y), kw...)
    B = _poly_mask(first(st), to; order, kw...)
    map(x -> _mask!(x, B; kw...), st)
    return st
end
# Array mask
_mask!(xs::RasterStack, to::AbstractArray; kw...) = map(x -> mask!(x; to, kw...),  xs)

# Polygon mask
function _mask!(A::RasterStackOrArray, poly::GI.AbstractGeometry; kw...)
    _mask!(A, GI.coordinates(poly))
end
# Array mask
function _mask!(A::AbstractRaster, to::AbstractArray; missingval=missingval(A))
    missingval isa Nothing && _nomissingerror()
    dimwise!(A, A, to) do a, t
        t === Rasters.missingval(to) ? missingval : a
    end
    return A
end

function _poly_mask(A::AbstractRaster, poly::AbstractVector; 
    order=(XDim, YDim), shape=:polygon
)
    missingval isa Nothing && _nomissingerror()
    # We need a tuple of all the dims in `order`
    # We also need the index locus to be the center so we are
    # only selecting cells more than half inside the polygon
    shifted_dims = map(d -> DD.maybeshiftlocus(Center(), d), dims(A))

    # Get the array as points
    pts = vec(collect(points(shifted_dims; order)))

    nodes = flat_nodes(poly)
    poly_bounds = map(1:length(order)) do i
        extrema((p[i] for p in nodes))
    end
    array_bounds = bounds(dims(A, order))
    is_crossover = map(poly_bounds, array_bounds) do (p_min, p_max), (a_min, a_max)
        if p_max >= a_max
            p_min <= a_max
        else
            p_max >= a_min
        end
    end |> all

    # Only run inpolygon if the polygon has any point in the bounding box
    if is_crossover
        # Check if theyre in the polygon
        if shape === :polygon
            # Use the first column of the output - the points in the polygon,
            # and reshape to match `A`
            inpoly = inpolygon(pts, poly)
            inpoly = BitArray(reshape(view(inpoly, :, 1), size(A)))
        elseif shape === :line
            # Use a tolerance of the average pixel size
            # This is not the most exact metric to use, but we are limited
            # to a single `atol` value.
            meansteps = map(b -> b[2] - b[1], bounds(A)) ./ size(A)
            averagepixel = max(meansteps...)/2
            # Join the line with itself reverse, to form a closed polygon.
            # There must be a better way...
            poly = vcat(poly, reverse(poly))
            inpoly = inpolygon(pts, poly; atol=averagepixel)
            # Take the sedond column of the output - the cells close to the line
            inpoly = BitArray(reshape(view(inpoly, :, 2), size(A)))
        else
            throw(ArgumentError("`shape` keyword must be :line or :polygon")) 
        end
    else
        inpoly = BitArray(undef, size(A))
        inpoly .= false
    end

    # Rebuild a with the masked values
    return rebuild(A; data=inpoly, missingval=false)
end

_nomissingerror() = throw(ArgumentError("Array has no `missingval`. Pass a `missingval` keyword compatible with the type, or use `rebuild(A; missingval=somemissingval)` to set it."))

const Pt{T<:Real} = Union{AbstractVector{T},NTuple{<:Any,T}}
const Poly = AbstractVector{<:Union{NTuple{<:Any,<:Real},AbstractVector{<:Real}}}

function unwrap_point(q::GI.AbstractPoint)
    (q.x, q.y)
end
unwrap_point(q) = q

"""
    boolmask(A::AbstractArray, [missingval])
    boolmask(T, A::AbstractArray, [missingval])

Create a mask array of `Bool` values, from any `AbstractArray`.


The array returned from calling `boolmask` on a `AbstractRaster` is a
[`Raster`](@ref) with the same size and fields as the original array.

# Arguments

- `T`: `BitArray` or `Array`
- `A`: An `AbstractArray`.
- `missingval`: The missing value of the source array. For [`AbstractRaster`](@ref) the
    default `missingval` is `missingval(A)`, for all other `AbstractArray`s it is `missing`.

# Example

```jldoctest
using Rasters, Plots, Dates
wc = Raster(WorldClim{Climate}, :prec; month=1)
boolmask(wc) |> plot

savefig("build/boolmask_example.png")
# output
```

![boolmask](boolmask_example.png)
"""
function boolmask end
function boolmask(A::AbstractArray, missingval=_missingval_or_missing(A))
    boolmask(Array, A, missingval)
end
boolmask(T::Type, A::AbstractArray, missingval=missing) = _boolmask(T, A, missingval)
function boolmask(T::Type, A::AbstractRaster, missingval=_missingval_or_missing(A))
    rebuild(A; data=_boolmask(T, A, missingval), missingval=false)
end

function _boolmask(::Type{<:Array}, A::AbstractArray, missingval)
    dest = Array{Bool}(undef, size(A))
    return boolmask!(dest, A, missingval)
end
function _boolmask(::Type{<:BitArray}, A::AbstractArray, missingval)
    dest = BitArray(undef, size(A))
    return boolmask!(dest, A, missingval)
end

function boolmask!(dest::AbstractArray{Bool}, src::AbstractArray, missingval::Missing)
    broadcast!(a -> !ismissing(a), dest, src)
end
function boolmask!(dest::AbstractArray{Bool}, src::AbstractArray, missingval=_missingval_or_missing(src))
    if missingval isa Number && isnan(missingval)
        broadcast!(a -> !isnan(a), dest, src)
    else
        broadcast!(a -> a !== missingval, parent(dest), parent(src))
    end
end

"""
    missingmask(A::AbstractArray, [missingval])

Create a mask array of `missing` or `true` values, from any `AbstractArray`.
For [`AbstractRaster`](@ref) the default `missingval` is `missingval(A)`,
for all other `AbstractArray`s it is `missing`.

The array returned from calling `missingmask` on a `AbstractRaster` is a
[`Raster`](@ref) with the same size and fields as the original array.

# Example

```jldoctest
using Rasters, Plots, Dates
wc = Raster(WorldClim{Climate}, :prec; month=1)
missingmask(wc) |> plot

savefig("build/missingmask_example.png")
# output
```

![missingmask](missingmask_example.png)
"""
function missingmask end
function missingmask(A::AbstractRaster)
    rebuild(A; data=missingmask(A, missingval(A)), missingval=missing, name=:missingmask)
end
missingmask(A::AbstractArray, missingval::Nothing) = missingmask(A, missing)
function missingmask(A::AbstractArray, missingval::Missing=missing)
    (a -> ismissing(a) ? missing : true).(parent(A))
end
function missingmask(A::AbstractArray, missingval)
    if missingval isa Number && isnan(missingval)
        (a -> isnan(a) ? missing : true).(parent(A))
    else
        (a -> a === missingval ? missing : true).(parent(A))
    end
end

