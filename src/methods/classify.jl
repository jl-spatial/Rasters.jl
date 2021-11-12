"""
    classify(x, pairs; lower=(>=), upper=(<), others=nothing)
    classify(x, pairs...; lower, upper, others)

Create a new array with values in `x` classified by the values in `pairs`.

If `Fix2` functions are not used in `pairs, the `lower` and `upper` keywords define
how the lower and upper boundaries are chosen.

If `others` is set other values not covered in `pairs` will be set to that values.

# Arguments

- `x`: a `Raster` or `RasterStack`
- `pairs`: each pair contains a value and a replacement, a tuple of lower and upper
    range and a replacement, or a Tuple of `Fix2` like `(>(x), <(y)`.

# Keywords

- `lower`: Which comparison (`<` or `<=`) to use for lower values, if `Fix2` are not used.
- `upper`: Which comparison (`>` or `>=`) to use for upper values, if `Fix2` are not used.
- `others`: A value to assign to all values not included in `pairs`.
    Passing `nothing` (the default) will leave them unchanged.

# Example

```jldoctest
using Rasters, Plots
A = Raster(WorldClim{Climate}, :tavg; month=1)
classes = (5, 15) => 10,
          (15, 25) => 20,
          (25, 35) => 30,
          >=(35) => 40
classified = classify(A, classes; others=0)
plot(classified; c=:magma)

savefig("build/classify_example.png")
# output
```

![classify](classify_example.png)

$EXPERIMENTAL
"""
function classify end
classify(A::AbstractRaster, pairs::Pair...; kw...) = classify(A, pairs; kw...)
function classify(A::AbstractRaster, pairs; lower=(>=), upper=(<), others=nothing)
    broadcast(A) do x
        _classify(x, pairs, lower, upper, others, missingval(A))
    end
end
classify(xs::RasterSeriesOrStack, values; kw...) = map(x -> classify(x, values; kw...),  xs)

"""
    classify!(x, pairs...; lower, upper, others)
    classify!(x, pairs; lower, upper, others)

Classify the values of `x` in-place, by the values in `pairs`.

If `Fix2` is not used, the `lower` and `upper` keywords

If `others` is set other values not covered in `pairs` will be set to that values.

# Arguments

- `x`: a `Raster` or `RasterStack`
- `pairs`: each pair contains a value and a replacement, a tuple of lower and upper
    range and a replacement, or a Tuple of `Fix2` like `(>(x), <(y)`.

# Keywords

- `lower`: Which comparison (`<` or `<=`) to use for lower values, if `Fix2` are not used.
- `upper`: Which comparison (`>` or `>=`) to use for upper values, if `Fix2` are not used.
- `others`: A value to assign to all values not included in `pairs`.
    Passing `nothing` (the default) will leave them unchanged.

# Example

`classify!` to disk, with key steps:
- copying a tempory file so we don't write over the RasterDataSources.jl version.
- use `open` with `write=true` to open the file with disk-write permissions.
- use `Float32` like `10.0f0` for all our replacement values and `other`, because
    the file is stored as `Float32`. Attempting to write some other type will fail.

```jldoctest
using Rasters, Plots, RasterDataSources
# Download and copy the file
filename = getraster(WorldClim{Climate}, :tavg; month=6)
tempfile = tempname() * ".tif"
cp(filename, tempfile)
# Define classes
classes = (5, 15) => 10.0f0,
          (15, 25) => 20.0f0,
          (25, 35) => 30.0f0,
          >=(35) => 40.0f0
# Open the file with write permission
open(Raster(tempfile); write=true) do A
    classify!(A, classes; others=0.0f0)
end
# Open it again to plot the changes
plot(Raster(tempfile); c=:magma)

savefig("build/classify_bang_example.png")
# output
```

![classify!](classify_bang_example.png)

$EXPERIMENTAL
"""
classify!(A::AbstractRaster, pairs::Pair...; kw...) = classify!(A, pairs; kw...)
function classify!(A::AbstractRaster, pairs; lower=(>=), upper=(<), others=nothing)
    broadcast!(A, A) do x
        _classify(x, pairs, lower, upper, others, missingval(A))
    end
end
function classify!(xs::RasterSeriesOrStack; kw...)
    map(x -> classify!(x; kw...),  xs)
    return xs
end

# _classify
# Classify single values
function _classify(x, pairs, lower, upper, others, missingval)
    x === missingval && return x
    # Use a fold instead of a loop, for type stability
    found = foldl(pairs; init=nothing) do found, (find, replace)
        if found isa Nothing && _compare(find, x, lower, upper)
            replace
        else
            found
        end
    end
    if found isa Nothing
        if others isa Nothing
            return x
        else
            return others
        end
    else
        return found
    end
end
function _classify(x, pairs::AbstractMatrix, lower, upper, others, missingval)
    x === missingval && return x
    found = false
    if size(pairs, 2) == 2
        for i in 1:size(pairs, 1)
            find = pairs[i, 1]
            if _compare(find, x, lower, upper)
                x = pairs[i, 2]
                found = true
                break
            end
        end
    elseif size(pairs, 2) == 3
        for i in 1:size(pairs, 1)
            find = pairs[i, 1], pairs[i, 2]
            if _compare(find, x, lower, upper)
                x = pairs[i, 3]
                found = true
                break
            end
        end
    else
        throw(ArgumentError("pairs Array must be a N*2 or N*3 matrix"))
    end
    if !found && !(others isa Nothing)
        x = others
    end
    return x
end

_compare(find, x, lower, upper) = find === x
_compare(find::Base.Fix2, x, lower, upper) = find(x)
_compare((l, u)::Tuple, x, lower, upper) = lower(x, l) && upper(x, u)
_compare((l, u)::Tuple{<:Base.Fix2,<:Base.Fix2}, x, lower, upper) = l(x) && u(x)


