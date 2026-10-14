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
        items = readmarks(f, key, Vector{MatRef})
        length(items) == $n || error(
            "cell \"", keyname(key), "\" has ", length(items), " items, not ", $n,
        )
        return ($(reads...),)
    end
end

"""
The marks of a cell array or of one field of a struct array, shaped as asked. MATLAB has no 1-D
arrays, so a vector is held as a 1xN or an Nx1 and is read through a matrix. A writer that
keeps Julia's shape, as this package does for an empty `Vector`, stores rank 1, read as it is.
"""
readmarks(f::MatFile, key, ::Type{Array{MatRef, N}}) where {N} = matread(f, key, Array{MatRef, N})
function readmarks(f::MatFile, key, ::Type{Vector{MatRef}})
    isone(length(matsize(f, key))) && return matread(f, key, Vector{MatRef})
    return vec(matread(f, key, Matrix{MatRef}))
end

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
