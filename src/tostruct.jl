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

A field `d` cannot describe gets no type and no field. A struct with no fields and an empty
cell hold nothing to take a type from, so a comment stands in the field's place saying which
it was:

```julia
struct Cfg
    gain::Float64
    # opt: a struct with no fields in a template, so its type is unknown
end
```

An empty array of numbers or text is described, since it carries its own element type.
[`@matstructs`](@ref) takes several templates to describe more.
"""
function matstructs(d::Record, name::Symbol)
    defs = String[]
    structdef!(defs, Set{String}(), String[], d, String(name), "")
    return join(defs, "\n")
end

"The path of the field `k` of the record at `path`, as the messages name it."
childpath(path::String, k::String) = isempty(path) ? k : string(path, ".", k)

"Record the path of a field no template describes, once."
function pushpath!(left::Vector{String}, path::String, k::String)
    p = childpath(path, k)
    p in left || push!(left, p)
    return left
end

"""
Is `v` a cell array rather than one stored value? A tuple is a cell, and so is an array that
holds anything other than numbers or text.
"""
iscellvalue(v) = v isa Tuple ||
    (v isa AbstractArray && !(eltype(v) <: Union{Number, AbstractChar, AbstractString}))

"""
Does `v` say what type its field has? A struct with no fields and an empty cell do not: neither
holds anything to take a type from, so a template that has one cannot describe that field. An
empty array of numbers or text does say, since it carries its own element type.
"""
isdescribed(v) = !((v isa Record || iscellvalue(v)) && isempty(v))

"What kind of empty value `v` is, for a message."
emptykind(v) = v isa Record ? "a struct with no fields" : "an empty cell"

"""
Add the definition for `d`, after the definitions it uses, and give back its type name.

A field no template describes is left out, since there is no type to write for it, and its
path is added to `left`. The definition keeps a comment in its place.
"""
function structdef!(
        defs::Vector{String}, taken::Set{String}, left::Vector{String}, d::Record,
        name::String, path::String,
    )
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
        if !isdescribed(v)
            pushpath!(left, path, k)
            push!(
                lines,
                string("    # ", k, ": ", emptykind(v), " in a template, so its type is unknown"),
            )
            continue
        end
        ftype = fieldtypestring!(
            defs, taken, left, v, string(tname, uppercasefirst(k)), childpath(path, k),
        )
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

function fieldtypestring!(
        defs::Vector{String}, taken::Set{String}, left::Vector{String}, v, name::String,
        path::String,
    )
    v isa Record && return structdef!(defs, taken, left, v, name, path)
    if iscellvalue(v) && !isempty(v)
        # A tuple is a cell of one row, as `matwrite` writes it.
        N = v isa Tuple ? 1 : ndims(v)
        if all(x -> x isa Record, v) && allequal(Set(recordkeys(x)) for x in v)
            # One struct for every item; its field types come from the first item.
            return arraytype(structdef!(defs, taken, left, first(v), name, path), N)
        elseif all(isplain, v) && allequal(leaftype(x) for x in v)
            return arraytype(leaftype(first(v)), N)
        end
        items = String[
            fieldtypestring!(defs, taken, left, x, string(name, i), string(path, i))
                for (i, x) in enumerate(v)
        ]
        return string("Tuple{", join(items, ", "), "}")
    end
    return leaftype(v)
end

"""
One record out of several templates, holding the fields all of them describe.

A field is kept only if every template describes it. A key that one template lacks, or holds
empty, is left out and its path is added to `left`. The reason is the same for both: the type
names every field it reads, so a file of that shape could not be read into it. Give fewer
templates if one of them is not representative.

Merging reaches into structs. Inside a cell array it does not: one template's cell is taken
whole, since the items of a cell are matched by position and two files need not agree on how
many there are.
"""
function mergerecords(ds::Vector, left::Vector{String}, path::String)
    shared = intersect((Set(recordkeys(d)) for d in ds)...)
    for d in ds, k in recordkeys(d)
        k in shared || pushpath!(left, path, k)
    end
    out = Dict{String, Any}()
    for k in shared
        vs = Any[recordget(d, k, Symbol(k)) for d in ds]
        empties = filter(!isdescribed, vs)
        # Keeping an empty one hands the field to `structdef!`, which leaves it out and says
        # why, so a missing key and an empty one are reported together.
        out[k] = isempty(empties) ? mergefields(vs, left, childpath(path, k)) : first(empties)
    end
    return out
end

"""
The value to take one field's type from, out of what each template holds for it. Two templates
that describe the field differently stop with an error, since one field type cannot match both.
"""
function mergefields(vs::Vector, left::Vector{String}, path::String)
    all(v -> v isa Record, vs) && return mergerecords(vs, left, path)
    for v in vs
        agree(first(vs), v) || error(
            "the templates disagree about \"", path, "\": one holds ", leaftype(first(vs)),
            ", another holds ", leaftype(v),
        )
    end
    return first(vs)
end

"Do two values from different templates imply one field type?"
function agree(a, b)
    (a isa Record) == (b isa Record) || return false
    iscellvalue(a) == iscellvalue(b) || return false
    a isa Record && return Set(recordkeys(a)) == Set(recordkeys(b))
    iscellvalue(a) && return length(a) == length(b) && all(p -> agree(p...), zip(a, b))
    return leaftype(a) == leaftype(b)
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
    @matstructs Name ["first.mat", "second.mat"] "variable"

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

## When one file is not enough

One template is one sample, so it cannot describe a field that is empty in it: a struct with
no fields and an empty cell hold nothing to take a type from. Such a field is **left out** of
the type, with a warning that names it, rather than guessed at.

Give a list of templates to describe more. A field is then named only if **every** template
describes it, which keeps the type readable from every file of that shape:

```julia
@matstructs Run ["runs/run_001.mat", "runs/run_042.mat"] "run"
```

- A field that one template lacks, or holds empty, is left out and named in the warning.
- A field two templates describe differently, such as a scalar in one and a matrix in the
  other, stops with an error. One field type cannot match both.
- Merging reaches into structs, but not into the items of a cell array.

Read a field the type leaves out where it is there, with its own typed read:

```julia
f = matopen("today.mat")
run = matread(f, "run", Run)
opt = isempty(matkeys(f, "run/opt")) ? nothing : matread(f, "run/opt", Opt)
```

Write `Opt` by hand, or print it with `matstructs(matread("runs/run_042.mat")["run"]["opt"],
:Opt)`. If a template is not representative, leaving it out of the list is the other answer.

A relative path is taken from the file the macro is in, as `include` does. Every template is
recorded as a dependency, so a package that uses the macro is compiled again when one of them
changes.
"""
macro matstructs(name, path, var...)
    name isa Symbol || error("@matstructs: the first argument is the name of the type")
    length(var) <= 1 && all(v -> v isa String || v === :unwrap, var) ||
        error("@matstructs: give at most one variable name, as a string literal, or `unwrap`")
    files = templatefiles(path, __source__)
    ds = Record[templaterecord(matread(file), file, var) for file in files]
    left = String[]
    merged = mergerecords(ds, left, "")
    defs = String[]
    structdef!(defs, Set{String}(), left, merged, String(name), "")
    isempty(left) || @warn string(
        "@matstructs: ", name, " does not name ", join(left, ", "),
        ". Each one is missing from a template, or empty in one, so a file of that shape ",
        "could not be read into the type. Read each where it is there, as in ",
        "`matread(f, \"cfg/opt\", T)`, or leave out a template that is not representative.",
    )
    code = Meta.parseall(join(defs, "\n"))
    deps = Expr[:(Base.include_dependency($file)) for file in files]
    return esc(Expr(:toplevel, deps..., code.args..., nothing))
end

"""
The template files the macro was given: one path, or a list of them. A relative path is taken
from the file the macro is in, as `include` does.
"""
function templatefiles(path, source::LineNumberNode)
    paths = if path isa String
        String[path]
    elseif path isa Expr && path.head === :vect && all(p -> p isa String, path.args)
        isempty(path.args) && error("@matstructs: give at least one template")
        String[p for p in path.args]
    else
        error("@matstructs: the template is a path as a string literal, or a list of them")
    end
    dir = isnothing(source.file) ? pwd() : dirname(String(source.file))
    return String[abspath(dir, p) for p in paths]
end

"The record one template contributes: the whole file, or the one variable the macro was given."
function templaterecord(d::Record, file::String, var)
    isempty(var) && return d
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
    v = d[key]
    v isa Record || error("@matstructs: \"", key, "\" is not a struct, so it has no fields")
    return v
end
