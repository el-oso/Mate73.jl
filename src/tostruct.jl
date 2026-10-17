# From a nested Dict or NamedTuple to nested structs: write the types once from a sample, then convert.
#
# `matstructs` looks at a Dict, such as one `matread(path)` or MAT.jl gives back, and writes
# the struct definitions its shape implies. You paste them into your code. `tostruct` then
# turns any Dict of that shape into those types, so the rest of the program sees concrete,
# nested fields instead of `Dict{String,Any}`.

const Record = Union{AbstractDict, NamedTuple}
const Items = Union{AbstractArray, Tuple}

recordkeys(d::Record) = String[String(k) for k in keys(d)]
# A Dict may have String or Symbol keys; a NamedTuple field is reached by a constant Symbol.
hasrecordkey(d::AbstractDict, k::String, s::Symbol) = haskey(d, k) || haskey(d, s)
hasrecordkey(nt::NamedTuple, ::String, s::Symbol) = haskey(nt, s)
recordget(d::AbstractDict, k::String, s::Symbol) = haskey(d, k) ? d[k] : d[s]
recordget(nt::NamedTuple, ::String, s::Symbol) = getfield(nt, s)

"""
    matstructs(d, name::Symbol) -> String

Write the Julia source of struct definitions that match the shape of `d`, a nested Dict or
NamedTuple, with `name` for the
outermost one. Print it and paste it into your code.

```julia
d = matread("sample.mat")["cfg"]
print(matstructs(d, :Cfg))
```

| in the Dict | the field type |
|---|---|
| a `Dict` or `NamedTuple` | a struct of its own, named after the parent and the field |
| an array or tuple of `Dict`s of the same shape | an array of one struct |
| an array whose items share one type | an array of that type |
| an array of mixed items | a `Tuple` of their types |
| anything else | its own type, such as `Matrix{Float64}` or `String` |

Fields are written in sorted order. A key that is not a valid Julia name is written as
`var"key"`. Check the result: it describes this sample, so a field that is sometimes a scalar
and sometimes a matrix needs the wider type written in by hand.
"""
function matstructs(d::Record, name::Symbol)
    defs = String[]
    structdef!(defs, Set{String}(), d, String(name))
    return join(defs, "\n")
end

"Add the definition for `d`, after the definitions it uses, and give back its type name."
function structdef!(defs::Vector{String}, taken::Set{String}, d::Record, name::String)
    tname = name
    n = 1
    while tname in taken
        n += 1
        tname = string(name, n)
    end
    push!(taken, tname)
    lines = String[]
    for k in sort!(recordkeys(d))
        v = recordget(d, k, Symbol(k))
        ftype = fieldtypestring!(defs, taken, v, string(tname, uppercasefirst(k)))
        fname = Base.isidentifier(k) ? k : string("var\"", k, "\"")
        push!(lines, string("    ", fname, "::", ftype))
    end
    push!(defs, string("struct ", tname, "\n", join(lines, "\n"), isempty(lines) ? "" : "\n", "end\n"))
    return tname
end

"""
The type to write for one plain value. A 1x1 number is a number, since this package keeps a
MATLAB scalar as a 1x1 array, and one character is text, since MAT.jl gives a one-character
`char` as a `Char`.
"""
leaftype(v) = string(typeof(v))
leaftype(::AbstractChar) = "String"
leaftype(v::AbstractArray{<:Number}) = length(v) == 1 ? string(eltype(v)) : string(typeof(v))

"The array type of `N` dimensions holding `elt`, written the way Julia prints it."
arraytype(elt::String, N::Int) =
    N == 1 ? string("Vector{", elt, "}") : N == 2 ? string("Matrix{", elt, "}") :
    string("Array{", elt, ", ", N, "}")

"Is `x` one plain value rather than a container of several?"
isplain(x) = !(x isa Union{Items, Record}) || (x isa AbstractArray{<:Number} && length(x) == 1)

function fieldtypestring!(defs::Vector{String}, taken::Set{String}, v, name::String)
    v isa Record && return structdef!(defs, taken, v, name)
    iscontainer = v isa Tuple ||
        (v isa AbstractArray && !(eltype(v) <: Union{Number, AbstractChar, AbstractString}))
    if iscontainer && !isempty(v)
        # A tuple is a cell of one row, as `matwrite` writes it.
        N = v isa Tuple ? 1 : ndims(v)
        if all(x -> x isa Record, v) && allequal(Set(recordkeys(x)) for x in v)
            # One struct for every item; its field types come from the first item.
            return arraytype(structdef!(defs, taken, first(v), name), N)
        elseif all(isplain, v) && allequal(leaftype(x) for x in v)
            return arraytype(leaftype(first(v)), N)
        end
        items = String[fieldtypestring!(defs, taken, x, string(name, i)) for (i, x) in enumerate(v)]
        return string("Tuple{", join(items, ", "), "}")
    end
    return leaftype(v)
end

"""
    tostruct(T, d) -> T

Convert a nested Dict or NamedTuple, or any value inside one, into `T`, usually a type written
by [`matstructs`](@ref).

```julia
s = tostruct(Cfg, matread("run.mat")["cfg"])
s.limits.hi
```

A struct is filled field by field from the key of the same name, and nested structs, arrays of
structs and tuples are converted the same way. A number accepts a 1x1 array and an array
accepts a single number, since this package keeps MATLAB scalars as 1x1 arrays and MAT.jl
unwraps them. A tuple fills an array as a cell of one row. A key `T` names but `d` lacks stops
with an error.

The result has the concrete type `T`, whatever the Dict held.
"""
function tostruct end

@generated function tostruct(::Type{T}, d::Record) where {T}
    # A field declared as a Dict or NamedTuple keeps the value as it is.
    T <: Record && return :(convert($T, d)::$T)
    (isrecord(T) && isconcretetype(T)) ||
        return :(error("cannot convert to ", $T, ": it is not a struct type"))
    args = Expr[]
    for i in 1:fieldcount(T)
        k = String(fieldname(T, i))
        s = QuoteNode(fieldname(T, i))
        push!(
            args, :(
                tostruct(
                    $(fieldtype(T, i)),
                    hasrecordkey(d, $k, $s) ? recordget(d, $k, $s) :
                        error("no key \"", $k, "\" for a field of ", $T),
                )
            ),
        )
    end
    return :($T($(args...)))
end

tostruct(::Type{T}, v) where {T} = convert(T, v)::T
tostruct(::Type{String}, c::AbstractChar) = string(c)
tostruct(::Type{T}, v::AbstractArray) where {T <: Number} =
    (length(v) == 1 ? convert(T, only(v)) : convert(T, v))::T
tostruct(::Type{T}, v::Number) where {T <: AbstractArray} =
    convert(T, fill(v, ntuple(Returns(1), ndims(T))))::T

function tostruct(::Type{Array{E, N}}, v::AbstractArray) where {E, N}
    out = Array{E, N}(undef, size(v))
    for i in eachindex(out, v)
        out[i] = tostruct(E, v[i])
    end
    return out
end

# A tuple is a cell of one row, so it fills a vector or a 1xN array.
function tostruct(::Type{Array{E, N}}, v::Tuple) where {E, N}
    dims = ntuple(i -> i == N ? length(v) : 1, Val(N))
    out = Array{E, N}(undef, dims)
    for i in eachindex(out)
        out[i] = tostruct(E, v[i])
    end
    return out
end

@generated function tostruct(::Type{T}, v::Items) where {T <: Tuple}
    n = fieldcount(T)
    items = Expr[:(tostruct($(fieldtype(T, i)), v[$i])) for i in 1:n]
    return quote
        length(v) == $n || error("expected ", $n, " items for ", $T, ", got ", length(v))
        return ($(items...),)
    end
end

"""
    @matstructs Name "template.mat" "variable"
    @matstructs Name "template.mat" unwrap
    @matstructs Name "template.mat"

Define nested struct types from the shape of a template file, while the code is compiled.

The template is read when the macro runs, and [`matstructs`](@ref) writes the definitions,
which are placed where the macro stands. Any other file with the same structure is then read
into them with the typed reads, so the program that does the reading never sees a
`Dict{String,Any}` and works inside a small compiled program.

```julia
@matstructs Cfg "template.mat" "cfg"     # one variable
@matstructs Cfg "template.mat" unwrap    # the only variable, whatever it is called
@matstructs Run "template.mat"           # every variable, one field each

cfg = matread(matopen("today.mat"), "cfg", Cfg)
run = matread("today.mat", Run)
cfg.limits.hi
```

`unwrap` is for a file that wraps one struct in a name that changes from file to file, such as
the name the struct had in MATLAB or the name of the file. It drops that layer, so the types
describe the struct itself and every file of that shape reads into them whatever its variable
is called. The template must hold exactly one variable. Give the name at run time to read one:

```julia
f = matopen("today.mat")
cfg = matread(f, only(keys(f)), Cfg)
```

A relative path is taken from the file the macro is in, as `include` does. The template is
recorded as a dependency, so a package that uses the macro is compiled again when the
template changes.
"""
macro matstructs(name, path, var...)
    name isa Symbol || error("@matstructs: the first argument is the name of the type")
    path isa String || error("@matstructs: the template path must be a string literal")
    length(var) <= 1 && all(v -> v isa String || v === :unwrap, var) ||
        error("@matstructs: give at most one variable name, as a string literal, or `unwrap`")
    dir = isnothing(__source__.file) ? pwd() : dirname(String(__source__.file))
    file = abspath(dir, path)
    d = matread(file)
    if !isempty(var)
        key = if var[1] === :unwrap
            length(d) == 1 || error(
                "@matstructs: \"", file, "\" has ", length(d),
                " variables, so there is nothing to unwrap",
            )
            only(keys(d))
        else
            haskey(d, var[1]) ||
                error("@matstructs: \"", file, "\" has no variable \"", var[1], "\"")
            var[1]
        end
        d = d[key]
        d isa Record || error("@matstructs: \"", key, "\" is not a struct, so it has no fields")
    end
    code = Meta.parseall(matstructs(d, name))
    return esc(Expr(:toplevel, :(Base.include_dependency($file)), code.args..., nothing))
end
