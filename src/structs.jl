# Reading into a type of your own: a struct, a tuple, or an array of structs.
#
# The type you give says what every field holds, so each field is read with the typed read for
# its own type. Nothing passes through `Any`, and the whole read is settled while the program
# is compiled, so it works inside a small compiled program.

"""
Is `T` read one field at a time, rather than as one stored value?

The types the typed reads already know are stored values. A `NamedTuple` is a table here, and
a `Tuple` is a cell array, so both have their own methods.
"""
isrecord(::Type{T}) where {T} = isstructtype(T) && !(
    T <: Union{
        Number, AbstractChar, AbstractString, AbstractArray, AbstractDict, MatRef, DateTime,
        Tuple, NamedTuple,
    }
)

"The member `name` of the struct or object at `key`, named by its whole path for errors."
function childkey(f::MatFile, key, name::String)
    return MatPath(lookup(f, MatRef(address(f, key)), name), string(keyname(key), "/", name))
end

"""
    matread(f, name, T) -> T

Read a MATLAB struct or object into a struct type of your own.

Each field of `T` is read from the field of the same name, as the type that field is declared
with. A field may be any type the typed reads take, including another struct of your own, so
nested data comes back fully typed.

```julia
struct Limits
    lo::Float64
    hi::Float64
end

struct Settings
    gain::Float64
    mode::String
    weights::Matrix{Float64}
    limits::Limits
end

s = matread(f, "cfg", Settings)
s.limits.hi
```

`T` is built with its default constructor, `T(field1, field2, ...)`. A field the file holds
but `T` does not name is left unread. A field `T` names but the file does not hold stops with
an error.

You state the type, so this works inside a small compiled program.
"""
@generated function matread(f::MatFile, key, ::Type{T}) where {T}
    (isrecord(T) && isconcretetype(T) && fieldcount(T) > 0) || return :(
        error("cannot read \"", keyname(key), "\" as ", $T, ": this package has no read for it")
    )
    reads = Expr[
        :(matread(f, childkey(f, key, $(String(fieldname(T, i)))), $(fieldtype(T, i))))
            for i in 1:fieldcount(T)
    ]
    return :($T($(reads...)))
end

"""
    matread(f, name, Tuple{T1, T2, ...}) -> Tuple

Read a cell array whose items you know, one type for each item, in MATLAB's order.

```julia
runs = matread(f, "runs", Tuple{Matrix{Float64}, String, Settings})
```

This is the reverse of writing a `Tuple`, which becomes a cell array. The number of items must
match. You state every type, so this works inside a small compiled program.
"""
@generated function matread(f::MatFile, key, ::Type{T}) where {T <: Tuple}
    (isconcretetype(T) && !Base.isvatuple(T)) || return :(
        error("cannot read \"", keyname(key), "\" as ", $T, ": give the type of every item")
    )
    n = fieldcount(T)
    reads = Expr[:(matread(f, items[$i], $(fieldtype(T, i)))) for i in 1:n]
    return quote
        items = matread(f, key, Matrix{MatRef})
        length(items) == $n || error(
            "cell \"", keyname(key), "\" has ", length(items), " items, not ", $n,
        )
        return ($(reads...),)
    end
end

"""
The marks of a cell array or of one field of a struct array, shaped as asked. MATLAB has no 1-D
arrays, so a vector is held as a 1xN or an Nx1 and is read through a matrix.
"""
readmarks(f::MatFile, key, ::Type{Array{MatRef, N}}) where {N} = matread(f, key, Array{MatRef, N})
readmarks(f::MatFile, key, ::Type{Vector{MatRef}}) = vec(matread(f, key, Matrix{MatRef}))

"""
An array of structs of your own. MATLAB keeps one either as a cell array, one struct per item,
or as a struct array, one array of marks per field. Both are read here.
"""
function readrecords(f::MatFile, key, ::Type{Array{T, N}}) where {T, N}
    isgroup(objinfo(f.h5, address(f, key))) && return readstructarray(f, key, Array{T, N})
    return readcellitems(f, key, Array{T, N})
end

"Is `key` a cell array?"
iscell(f::MatFile, key) = objinfo(f.h5, address(f, key)).mclass == "cell"

"""
Read a cell array item by item, each as `T`. A cell whose items share one type then reads
into an array of that type, such as a cell of text into `Matrix{String}`.
"""
function readcellitems(f::MatFile, key, ::Type{Array{T, N}}) where {T, N}
    items = readmarks(f, key, Array{MatRef, N})
    out = Array{T, N}(undef, size(items))
    for i in eachindex(items)
        out[i] = matread(f, items[i], T)
    end
    return out
end

"""
Does the field at `key` belong to a struct array? Each field of one is an array of marks with
no MATLAB class of its own. A cell held as the field of a single struct is marked `cell`.
"""
function isstructarrayfield(f::MatFile, key)
    oi = objinfo(f.h5, address(f, key))
    return oi.dt_class == DT_REFERENCE && isempty(oi.mclass)
end

"""
A struct array, read into an array of structs of your own. A single struct is a 1x1 struct
array in MATLAB, so it is read as an array of one.
"""
@generated function readstructarray(f::MatFile, key, ::Type{Array{T, N}}) where {T, N}
    (isconcretetype(T) && fieldcount(T) > 0) || return :(
        error("cannot read \"", keyname(key), "\" as ", $(Array{T, N}))
    )
    n = fieldcount(T)
    names = String[String(fieldname(T, i)) for i in 1:n]
    refs = Symbol[Symbol(:refs, i) for i in 1:n]
    loads = Expr[
        :($(refs[i]) = readmarks(f, childkey(f, key, $(names[i])), Array{MatRef, N})) for i in 1:n
    ]
    checks = Expr[
        :(
            size($(refs[i])) == size($(refs[1])) || error(
                "struct array \"", keyname(key), "\" has fields of different sizes",
            )
        ) for i in 2:n
    ]
    item = :($T($((:(matread(f, $(refs[i])[j], $(fieldtype(T, i)))) for i in 1:n)...)))
    return quote
        if !isstructarrayfield(f, childkey(f, key, $(names[1])))
            return fill(matread(f, key, T), ntuple(Returns(1), Val(N)))
        end
        $(loads...)
        $(checks...)
        out = Array{T, N}(undef, size($(refs[1])))
        for j in eachindex(out)
            out[j] = $item
        end
        return out
    end
end


# ── @matstruct: a struct whose fields say where they come from ─────────────────

"Does the struct or object at `key` hold `path`? Checks every step, and never stops with an error."
function haspath(f::MatFile, key, path::String)
    k = MatPath(address(f, key), keyname(key))
    for part in split(path, '/'; keepempty = false)
        name = String(part)
        name in matkeys(f, k) || return false
        k = childkey(f, k, name)
    end
    return true
end

"Read the field at `path` below `key` as `T`."
readfield(f::MatFile, key, path::String, ::Type{T}) where {T} = matread(f, childkey(f, key, path), T)

# An optional field: absent or empty in the file gives `nothing`.
function readfield(f::MatFile, key, path::String, ::Type{Union{Nothing, T}}) where {T}
    haspath(f, key, path) || return nothing
    k = childkey(f, key, path)
    objinfo(f.h5, address(f, k)).mempty && return nothing
    return matread(f, k, T)
end

"A field with a default, used when the file does not hold it."
function readfield(f::MatFile, key, path::String, ::Type{T}, default) where {T}
    haspath(f, key, path) || return convert(T, default)
    return readfield(f, key, path, T)
end

"""
Take one line of a `@matstruct` body apart: the Julia field name, its type, the path it is
read from, and its default expression if it has one.
"""
function matfield(line)
    default, hasdefault = nothing, false
    if Meta.isexpr(line, :(=)) && Meta.isexpr(line.args[1], :(::))
        # name::T = default
        line, default, hasdefault = line.args[1], line.args[2], true
    end
    if Meta.isexpr(line, :(::)) && line.args[1] isa Symbol
        return line.args[1], line.args[2], String(line.args[1]), default, hasdefault
    end
    if Meta.isexpr(line, :(=)) && line.args[1] isa Symbol
        # name = "path"::T, or name = "path"::T = default
        rhs = line.args[2]
        if Meta.isexpr(rhs, :(=))
            rhs, default, hasdefault = rhs.args[1], rhs.args[2], true
        end
        if Meta.isexpr(rhs, :(::)) && rhs.args[1] isa String
            return line.args[1], rhs.args[2], rhs.args[1], default, hasdefault
        end
    end
    return error(
        "@matstruct cannot read the line `", line, "`; write `name::T`, `name::T = default`,",
        " `name = \"path\"::T` or `name = \"path\"::T = default`",
    )
end

"""
    @matstruct struct Name
        field::T
        field::T = default
        field = "matlab/path"::T
        field = "matlab/path"::T = default
    end

Define a struct and the typed read that fills it from a MATLAB struct or object.

```julia
@matstruct struct Limits
    lo = "lower"::Float64           # the MATLAB field has another name
    hi = "upper"::Float64
end

@matstruct struct Settings
    gain::Float64
    mode::String = "fast"           # used when the file has no `mode`
    limits::Vector{Limits}          # a cell of structs, or a struct array
    weights::Union{Nothing, Matrix{Float64}}   # `nothing` when absent or empty
    offset = "calib/offset"::Float64          # a path into a nested struct
end

s = matread(f, "cfg", Settings)
```

Every field's path, type and default are known when the macro runs, so the read it writes is a
plain call for each field, and the whole read works inside a small compiled program. A field
whose type is another `@matstruct` struct, or an array of one, is read with that struct's own
read, so nesting goes as deep as the types do.

A field whose type is `Union{Nothing, T}` is optional without a default. Any other field the
file does not hold stops with an error, unless it has a default.
"""
macro matstruct(expr)
    Meta.isexpr(expr, :struct) || error("@matstruct takes a struct definition")
    ismut, head, body = expr.args
    name = head isa Symbol ? head : Meta.isexpr(head, :<:) ? head.args[1] : head
    name isa Symbol || error("@matstruct does not take a struct with type parameters")
    decls = Any[]
    reads = Expr[]
    for line in body.args
        (line isa LineNumberNode || line isa String) && (push!(decls, line); continue)
        fname, T, path, default, hasdefault = matfield(line)
        push!(decls, :($fname::$T))
        push!(
            reads,
            hasdefault ? :($readfield(f, key, $path, $T, $default)) :
                :($readfield(f, key, $path, $T)),
        )
    end
    return esc(
        quote
            $(Expr(:struct, ismut, head, Expr(:block, decls...)))
            function $(Mate73).matread(f::$(MatFile), key, ::Type{$name})
                return $name($(reads...))
            end
            $name
        end,
    )
end

"""
    matread(f, T) -> T
    matread(path, T) -> T

Read a whole file into a struct type of your own, one field for each variable, as
[`@matstructs`](@ref) writes for a template file.

```julia
@matstructs Run "template.mat"
run = matread("today.mat", Run)
```

Each field is read from the variable of the same name, as the type it is declared with. You
state the type, so this works inside a small compiled program.
"""
@generated function matread(f::MatFile, ::Type{T}) where {T}
    (isrecord(T) && isconcretetype(T)) || return :(
        error("cannot read a whole file as ", $T, ": it is not a struct type")
    )
    reads = Expr[
        :(matread(f, $(String(fieldname(T, i))), $(fieldtype(T, i)))) for i in 1:fieldcount(T)
    ]
    return :($T($(reads...)))
end

matread(path::String, ::Type{T}) where {T} = matread(matopen(path), T)
