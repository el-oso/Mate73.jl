# Functions and types

## Reading, the short way

These work out the type from the file. They cannot be used inside a small compiled program.

```@docs
matread(::String)
matread(::MATTE73.MatFile, ::Any)
```

## Reading several variables at once

```@docs
@matload
```

## Reading, with the type

```@docs
matopen
matread(::String, ::String, ::Type)
matread(::MATTE73.MatFile, ::MATTE73.MatRef, ::String, ::Type)
matread(::MATTE73.MatFile, ::Any, ::Type{<:Number})
matref
matclass
matsize
matkeys
matobjectclass
matread
MATTE73.MatFile
MATTE73.MatClass
MATTE73.MatRef
```

## Writing

```@docs
matwrite
MATTE73.MatWriter
push!(::MATTE73.MatWriter, ::String, ::Any)
```

**Use `matwrite(path, pairs...)` for the simple case.**

For a set of variables built in a loop, collect them first. Addresses inside the file depend
on the size of every variable. So nothing is written until the end.

```julia
w = MatWriter()
for (name, value) in results
    push!(w, name, value)
end
matwrite("out.mat", w)
```
