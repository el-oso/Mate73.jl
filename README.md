# Mate73.jl

[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://el-oso.github.io/Mate73.jl/dev/)
[![CI](https://github.com/el-oso/Mate73.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/el-oso/Mate73.jl/actions/workflows/CI.yml)
[![Coverage](https://coveralls.io/repos/github/el-oso/Mate73.jl/badge.svg?branch=master)](https://coveralls.io/github/el-oso/Mate73.jl?branch=master)

**This package reads and writes MATLAB `.mat` files of version 7.3. It uses only Julia code.
It does not use the HDF5 C library.**

MATLAB writes version 7.3 files when you use `save -v7.3`.

**Needs Julia 1.12 or newer.** That is the first release with the `juliac` tool, which is what
the small-program support is for.

## Example

```julia
using Mate73

d = matread("results.mat")             # every variable, in a Dict
d["A"]

matwrite("out.mat", "A" => d["A"], "label" => "hello")
```

One variable at a time:

```julia
f = matopen("results.mat")
keys(f)                                # the names of the variables
matsize(f, "A")                        # [128, 128]
A = matread(f, "A")                    # a Matrix{Float64}
```

## Two ways to read

**Use the short way. Give the type only if you build a small compiled program.**

| | short way | with the type |
|---|---|---|
| whole file | `matread(path)` | — |
| one variable | `matread(f, "A")` | `matread(f, "A", Matrix{Float64})` |
| one variable, no handle | — | `matread(path, "A", Matrix{Float64})` |
| works in a small program | no | yes |

Give a path instead of an open file when you want one variable and nothing else. Open the
file first when you want several, so it is read once rather than once for each variable.

The short way works out the type from the file, as MAT.jl does. It is the one to use in
ordinary Julia code.

The long way is for a tool named `juliac`. That tool builds a small program from Julia code.
Its option `--trim=safe` rejects any function that can return more than one type. So the
caller states the type instead.

A program that never calls the short way does not carry it. The build removes it.

## Reading several variables at once

**`@matload` gives you the short way and the fixed return type at the same time.**

You list the variables once. The macro writes one normal typed read for each line, with the
type written out. So it works inside a small compiled program.

```julia
v = @matload "results.mat" begin
    A::Matrix{Float64}          # an array
    n::Int64                    # a single number
    label::String               # one row of text
    gain = "cfg/gain"::Float64  # a field of a struct, under the name you choose
end

v.A
v.n
v.gain
```

You get a named tuple. Its type is known before the program runs.

The first item is a path or an open file. A path is opened once for the whole block. Give an
open file when you already have one:

```julia
f = matopen("results.mat")
v = @matload f A::Matrix{Float64}
```

A plain number type means a MATLAB scalar, which is a 1x1 array in the file. You get the
value. If the variable holds more than one value, this stops with an error.

The two line forms:

| you write | it reads |
|---|---|
| `name::Type` | the variable called `name` |
| `name = "a/path"::Type` | that path, under the name `name` |

The first item is a path, an open file, or a file and a mark. With `f, ref` every path in the
block starts at `ref`.

## Reading into your own types

**Give a struct type of your own, and a MATLAB struct comes back as that type, nested data and
all.** Nothing passes through `Dict{String,Any}`.

Think of a form with labelled boxes. You hand over the empty form; each box is filled from the
field of the same name, and a box may hold another whole form.

```julia
struct Limits
    lo::Float64
    hi::Float64
end

struct Settings
    gain::Float64          # a 1x1 in the file; the plain number comes back
    mode::String
    weights::Matrix{Float64}
    limits::Limits         # a struct inside the struct
end

s = matread(f, "cfg", Settings)
s.limits.hi
```

| you give | it reads |
|---|---|
| a struct type of your own | a struct or an object, one field per name |
| `Tuple{T1, T2, ...}` | a cell array, one type per item |
| `Array{T,N}` of your own struct | a cell array of structs, or a struct array |

Each field is read as the type it is declared with, so a field may be any type the typed reads
take, including another struct of your own, a tuple, or an array of structs. A field the file
holds but your type does not name is left unread. A field your type names but the file does not
hold stops with an error. Your type is built with its default constructor.

The types are stated, so this works inside a small compiled program, and `@matload` takes these
types too: `@matload f cfg::Settings`.

### When the names do not match: `@matstruct`

**`@matstruct` lets each field say where it comes from, what to use when it is missing, and
whether it may be absent.**

```julia
@matstruct struct Limits
    lo = "lower"::Float64                       # the MATLAB field has another name
    hi = "upper"::Float64
end

@matstruct struct Settings
    gain::Float64
    mode::String = "fast"                       # used when the file has no `mode`
    limits::Vector{Limits}                      # a cell of structs, or a struct array
    weights::Union{Nothing, Matrix{Float64}}    # `nothing` when absent or empty
    offset = "calib/offset"::Float64            # a path into a nested struct
end

s = matread(f, "cfg", Settings)
```

| you write | it reads |
|---|---|
| `name::T` | the field `name` |
| `name::T = default` | the field `name`, or `default` when the file has none |
| `name = "path"::T` | that path, which may go down through structs with `/` |
| `name = "path"::T = default` | that path, or `default` |
| `name::Union{Nothing, T}` | the field, or `nothing` when it is absent or empty |

The macro writes the struct and a `matread` method for it, with one typed read per field. Every
path, type and default is known when the macro runs, so the read works inside a small compiled
program, nested as deep as the types go.

## What the check does

When you give the type, the package does 3 checks against the file:

1. the kind of number, such as a whole number or a decimal number
2. the width in bytes
3. the sign, for whole numbers

If a check fails, the package stops with an error. It does not read the bytes as the wrong
type.

Use `matclass` first if you do not know what is in the file. It gives a name for the type. It
gives `MAT_UNSUPPORTED` for a type this package does not read. It does not stop with an error.

## Order of the dimensions

**You get the same array that MATLAB shows. Nothing is turned around.**

MATLAB and Julia both put the first dimension down the columns. The file keeps the dimensions
in the opposite order. The two effects cancel.

## What this package reads and writes

**It reads far more than it writes.** The last column says whether `matwrite` can put the type
back.

| MATLAB type | you get | written |
|---|---|---|
| `double`, `single` | `Array{Float64,N}`, `Array{Float32,N}` | yes |
| `int8` to `int64`, `uint8` to `uint64` | `Array{T,N}` | yes |
| `logical` | `Array{Bool,N}` | yes |
| `char`, one row | `String` | yes |
| empty arrays | the shape stays, such as `0x3` | yes |
| `cell` | `Array{MatRef,N}`, one mark for each item | yes, from a `Tuple` or an `Array{Any,N}` |
| `struct` | fields by path; `matkeys` gives the names | yes, from a `NamedTuple` or a `Dict` |
| complex numbers | `Array{Complex{T},N}` | no |
| `char`, any shape | `Array{Char,N}` | yes |
| struct arrays | each field is an `Array{MatRef,N}` | as a cell array of structs |
| `datetime` | `Array{DateTime,N}` | no |
| `string`, `categorical` | `Array{String,N}` | no |
| `table` | a `NamedTuple` of columns | as a struct of columns |
| objects of a class you wrote | properties by path | as a struct of properties |
| function handles | the values MATLAB stored, by path | as a struct of the stored values |
| objects of a class written before 2008 | properties by path | as a struct of properties |

## Boxes with mixed contents

**A cell array gives you marks, not values. You follow one mark at a time.**

Think of a cloakroom. You get a numbered ticket, not the coat. You hand back one ticket and
get one coat.

The items in a cell array can have different types. A function that returns all of them at
once would have no single type. So you get one mark for each item. The mark type is `MatRef`.

```julia
cells = matread(f, "c", Matrix{MatRef})
matclass(f, cells[1])                     # look before you choose a type
matread(f, cells[1], Matrix{Float64})     # follow the mark

matkeys(f, "s")                           # the field names of a struct
matread(f, "s/a", Matrix{Float64})        # one field, by path
```

A cell inside a cell gives you more marks. The steps stay the same.

**A path can also start at a mark.** This is how you read a field of a struct held in a cell:

```julia
runs = matread(f, "runs", Matrix{MatRef})
one = runs[1, 1]

matread(f, one, "count", Float64)                # one number
matread(f, one, "inner/values", Matrix{Float64}) # a field of a field
matref(f, one, "inner")                          # step down without reading

v = @matload f, one begin                        # or read several at once
    count = "count"::Float64
    values = "inner/values"::Matrix{Float64}
end
```

## Objects of a class

**An object holds no data. It holds numbers that point into a table.**

Think of a library catalogue card. The card is not the book. The card tells you the shelf.

MATLAB keeps the table in a hidden part of the file. This package follows the numbers for you.
An object then behaves like a struct.

```julia
matobjectclass(f, "obj")                  # "TestClasses.BasicClass"
matkeys(f, "obj")                         # the property names
matread(f, "obj/a", Matrix{Float64})      # one property, by path
```

Properties added later with `addprop` are in the list too. An object held by another object
is found as well.

A `datetime`, a `string`, a `categorical` and a `table` are objects too, and the package knows
the rule for each.

A saved function handle holds no code. MATLAB stores a named handle such as `@sin` as the
name `sin`, and an anonymous one such as `@(x) x` as the text of the expression plus the
values it captured. It reads as a set of named values, like a struct. You can see what a file
referred to. You cannot call it from Julia.

## Tables

**A table reads as a named tuple of columns.**

A named tuple of vectors is already a column table, so anything that reads the Tables.jl
interface takes the result as it is. This package needs no dependency for that.

```julia
t = matread(f, "flights")     # every column, with the types taken from the file
t.Customer

using DataFrames
DataFrame(t)
```

For a small compiled program you state the columns and their types. Each type is the type of
a whole column, so it is a `Vector`:

```julia
t = matread(f, "flights", NamedTuple{
    (:FlightNum, :Customer),
    Tuple{Vector{Float64}, Vector{String}},
})
```

You may ask for some of the columns only, in any order.

## Writing

```julia
matwrite("out.mat", "A" => A, "flags" => flags, "label" => "hello")
```

**A named tuple becomes a struct. A tuple becomes a cell array. Both nest.**

```julia
matwrite(
    "run.mat",
    "cfg"  => (gain = 2.5, mode = "fast", limits = (1.0, 10.0)),
    "runs" => ([1.0 2.0], "second", (name = "third", ok = true)),
)
```

| you give | MATLAB sees |
|---|---|
| an `Array` of numbers or `Bool` | an array of the matching type |
| one number or `Bool` | a 1x1 array |
| a `String` | text |
| a `NamedTuple` | a struct, one field per name |
| a `Tuple` | a cell array of one row |

Every type above is settled while your program is compiled, so writing those works inside a
small compiled program, as reading does.


A result written from a named tuple reads back into one:

```julia
matwrite("out.mat", "gain" => 2.5, "label" => "run 3")

v = @matload "out.mat" begin
    gain::Float64
    label::String
end
```

The package does not compress. Files are therefore larger than the files MATLAB writes.

### Writing back what you read

**A `Dict` becomes a struct. Any other array, such as `Array{Any}`, becomes a cell array of
the same shape.** These are what `matread(path)` and MAT.jl give back, so a whole file read
either way can be written again:

```julia
matwrite("copy.mat", matread("original.mat"))
matwrite("copy.mat", MAT.matread("original.mat"))
```

| you give | MATLAB sees |
|---|---|
| an `AbstractDict` | a struct, one field per key |
| any other array, such as `Array{Any}` | a cell array of the same shape |
| a `Char` or an `Array{Char}` | text, keeping its shape |
| a range, a view or a `BitArray` | an array of the matching type |

With MAT.jl loaded as well, its own types are written in a simpler form:

| MAT.jl gives | MATLAB sees |
|---|---|
| `MatlabStructArray` | a cell array of structs, of the same shape |
| `MatlabTable` | a struct with one field per column |
| `MatlabClassObject`, `MatlabOpaque`, `FunctionHandle` | a struct of their properties; the class is lost |

The type of each value inside a `Dict` or an `Array{Any}` is found only while the program
runs, so these cannot be used inside a small compiled program. Use a `NamedTuple` and a
`Tuple` there.

## Where the package stops

**Read this part first: two limits give you an answer that is not the one you asked for.**

Everything else here either works or stops with an error. These 2 do neither.

**The order of struct fields.** `matkeys` gives the names in the order the file holds them.
MATLAB may show them in another order. Every name is right and every value is right. Only the
order can differ.

**Arrays of objects.** One variable can stand for many objects. This package uses the first
one. `matobjectclass`, `matkeys` and every property path describe that first object, and say
nothing about the rest.

**A MATLAB class with no rule of its own.** `datetime`, `string`, `categorical` and `table`
each have a rule that turns their stored parts into the value MATLAB shows. `duration` and
`calendarDuration` do not, so you get a `Dict` of their properties instead. That is the same
thing you get for a class you wrote yourself, which is the intended answer there and a partial
one here.

### What stops with an error

| you asked for | what happens |
|---|---|
| a sparse array | error |
| a `categorical` element MATLAB shows as `<undefined>` | error; there is no text to give |
| a property MATLAB keeps in the table rather than beside it | error |
| an empty `Tuple`, on write | error; an empty `Array{Any}` writes an empty cell |
| text above code point 65535, as `Array{Char,N}` | 2 units, not 1; the `String` method joins them |

### What is not built yet

- **Writing** complex numbers, `datetime`, `string` or `categorical`. All of these read.
- **Writing struct arrays, tables and objects as themselves.** They are written in the simpler
  form above, so MATLAB reads a cell array or a struct in their place.
- **Writing sparse arrays as sparse.** A sparse array is written as a full one.
- **Compression on write.** Every array goes in one block, so files are larger than MATLAB's.
- **The row names of a table.** Only the columns are read.
- **The value a class gives a property in its own definition.** An object that never set the
  property lists no property at all.
- **Calling a function handle.** The file holds a name, or the text of an expression, never
  code.

The package reads the shapes MATLAB writes. HDF5 that MATLAB would never write stops with an
error: fractal heap groups, superblock versions 1 and 3, data layout version 4, shared header
messages, and filters other than deflate and shuffle.

`keys(f)` lists 2 names MATLAB keeps for itself, `#refs#` and `#subsystem#`. Skip them if you
only want your own variables.

## Tests

**Every value is compared against a second, independent reader.**

The tests use MAT.jl. That package reads through the HDF5 C library. It shares no code with
this one. The test files come from MATLAB itself.

Files that this package writes are read back through the same C library. That library checks
the internal totals in the file. A bad file fails there. A file cannot pass by being wrong in
the same way twice.

## How this package was written

**Claude wrote much of this package, with a human directing and reviewing it.** The commit log
says which changes were assisted.

This is worth knowing because a reader deserves to judge the code on the right terms. The
answer to "is it correct?" does not rest on who typed it: every value is checked against a
second reader that shares no code with this one, and the file format work is checked against
files MATLAB itself wrote. Those checks are in the section above, and you can run them.

## The small-program check

**A test proves that this package works inside a small compiled program.**

Two checks run, and they cover different things.

1. `trim/trimcheck.jl` runs the compiler check on every entry point. It finds the same
   problems the real build finds.
2. `juliac/build.jl` builds a real program and runs it. This step also links the program and
   starts it. The first check does neither.

Run them yourself:

```
julia --project=. juliac/build.jl
```

The build fails unless the program prints the same answer as normal Julia code.
