# Writes what a JLD2 file holds as a MATLAB file. JLD2 stores Julia's own types, so each value
# is first turned into one this package writes: a stored struct into a named tuple, which
# becomes a MATLAB struct.
module Mate73JLD2Ext

using Mate73: Mate73, MatWriter, Writable
using JLD2: JLDFile, Group

const Text = Union{AbstractString, AbstractChar}

"""
    matwrite(path, f::JLD2.JLDFile)

Write every variable of an open JLD2 file as a variable of a MATLAB file.

```julia
using JLD2
jldopen(f -> matwrite("out.mat", f), "data.jld2")
```

| in the JLD2 file | in the MATLAB file |
|---|---|
| a struct, whether or not its type is defined here | a struct, one field per field |
| a group | a struct, one field per member |
| a `Dict` with `String` or `Symbol` keys | a struct, one field per key |
| a `Symbol` | text |
| a range | an array |
| anything this package writes | the same as [`matwrite`](@ref) |

A value with no MATLAB form, such as `nothing` or a complex number, stops with an error that
names where it is, rather than being left out.
"""
function Mate73.matwrite(path::String, f::Union{JLDFile, Group})
    w = MatWriter()
    for k in keys(f)
        push!(w, k, tomat(f[k], k))
    end
    return Mate73.matwrite(path, w)
end

tomat(x::Union{Writable, Text}, ::String) = x
tomat(s::Symbol, ::String) = String(s)
tomat(a::AbstractArray{<:Union{Writable, Text}}, ::String) = a
tomat(t::Tuple, at::String) = ntuple(i -> tomat(t[i], at * "{" * string(i) * "}"), length(t))
tomat(nt::NamedTuple, at::String) =
    NamedTuple{keys(nt)}(map(k -> tomat(nt[k], at * "." * String(k)), keys(nt)))
# A number with no MATLAB class here, such as a complex number, is not written as its fields.
tomat(x::Number, at::String) = error("cannot write " * at * ": " * string(typeof(x)) * " has no MATLAB form")

function tomat(a::AbstractArray, at::String)
    out = Array{Any}(undef, size(a))
    for (j, i) in enumerate(CartesianIndices(a))
        out[j] = tomat(a[i], at * "(" * join(Tuple(i), ", ") * ")")
    end
    return out
end
tomat(g::Group, at::String) = Dict{String, Any}(k => tomat(g[k], at * "." * k) for k in keys(g))

function tomat(d::AbstractDict, at::String)
    out = Dict{String, Any}()
    for (k, v) in d
        k isa Union{AbstractString, Symbol} ||
            error("cannot write " * at * ": a MATLAB struct needs text keys, not " * string(typeof(k)))
        out[String(k)] = tomat(v, at * "." * String(k))
    end
    return out
end

# Any other struct, read with its type or as JLD2's stand-in for a type not defined here. The
# stand-in keeps its fields behind `getproperty`, so the fields are found that way.
function tomat(x, at::String)
    names = propertynames(x)
    (isstructtype(typeof(x)) && !isempty(names)) ||
        error("cannot write " * at * ": " * string(typeof(x)) * " has no MATLAB form")
    return NamedTuple{Tuple(names)}(map(p -> tomat(getproperty(x, p), at * "." * String(p)), names))
end

end # module Mate73JLD2Ext
