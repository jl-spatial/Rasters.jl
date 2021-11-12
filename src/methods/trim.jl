"""
    trim(A::AbstractRaster; dims::Tuple, pad::Int)

Trim `missingval` from `A` for axes in dims, returning a view of `A`.

By default `dims=(X, Y)`, so that trimming keeps the area of `X` and `Y`
that contains non-missing values along all other dimensions.

The trimmed size will be padded by `pad` on all sides, although
padding will not be added beyond the original extent of the array.

# Example

Create trimmed layers of Australian habitat heterogeneity.

```jldoctest
using Rasters, Plots
layers = (:evenness, :range, :contrast, :correlation)
st = RasterStack(EarthEnv{HabitatHeterogeneity}, layers)
plot(st)

# Roughly cut out australia
ausbounds = X(Between(100, 160)), Y(Between(-10, -50))
aus = st[ausbounds...]
a = plot(aus)

# Trim missing values and plot
b = plot(trim(aus))

savefig(a, "build/trim_example_before.png")
savefig(b, "build/trim_example_after.png")
# output
```

### Before `trim`:

![before trim](trim_example_before.png)

### After `trim`:

![after trim](trim_example_after.png)

$EXPERIMENTAL
"""
function trim(A::RasterStackOrArray; dims::Tuple=(X(), Y()), pad::Int=0)
    # Get the actual dimensions in their order in the array
    dims = commondims(A, dims)
    # Get the range of non-missing values for each dimension
    ranges = _trimranges(A, dims)
    # Add paddding
    padded = map(ranges, map(d -> size(A, d), dims)) do r, l
        max(first(r)-pad, 1):min(last(r)+pad, l)
    end
    dims = map(rebuild, dims, padded)
    return view(A, dims...)
end

# Tracks the status of an index for some subset of dimensions of an Array
# This lets us track e.g. the X/Y indices that have only missing values
# accross all other dimensions.
# This is a hack to work with DiskArrays broadcast chunking without allocations.
struct AxisTrackers{N,Tr,D,TD} <: AbstractArray{Bool,N}
    tracking::Tr
    dims::D
    trackeddims::TD
end
function AxisTrackers(tracking::T, dims::D, trackeddims::TD) where {T,D,TD}
    AxisTrackers{length(dims),T,D,TD}(tracking, dims, trackeddims)
end
function AxisTrackers(dims::Tuple, trackeddims::Tuple)
    tracking = map(trackeddims) do td
        (_ -> false).(td)
    end
    return AxisTrackers(tracking, dims, trackeddims)
end

Base.axes(A::AxisTrackers) = map(d -> axes(d, 1), A.dims)
Base.size(A::AxisTrackers) = map(length, A.dims)
Base.getindex(A::AxisTrackers, I...) = map(getindex, A.tracking, _trackedinds(I)) |> any
function Base.setindex!(A::AxisTrackers, x, I::Int...)
    map(A.tracking, _trackedinds(A, I)) do axis, i
        axis[i] |= x
    end
end

function _trackedinds(A, I)
    # Wrap indices in dimensions so we can sort and filter them
    Id = map((d, i) -> DD.basetypeof(d)(i), A.dims, I)
    # Get just the tracked dimensions
    Itracked = dims(Id, A.trackeddims)
    # Get the indices for the tracked dimensions
    return map(val, Itracked)
end

# Get the ranges to trim to for dimensions in `dims`
function _trimranges(A, targetdims)
    # Broadcast over the array and tracker to mark axis indices
    # as being missing or not
    trackers = AxisTrackers(dims(A), targetdims)
    _update!(trackers, A)
    # Get the ranges that contain all non-missing values
    cropranges = map(trackers.tracking) do a
        f = findfirst(a)
        l = findlast(a)
        f = f === nothing ? firstindex(a) : f
        l = l === nothing ? lastindex(a) : l
        f:l
    end
    return cropranges
end

_update!(tr::AxisTrackers, A::AbstractRaster) = tr .= A .!== missingval(A)
_update!(tr::AxisTrackers, st::AbstractRasterStack) = map(A -> tr .= A .!== missingval(A), st)

