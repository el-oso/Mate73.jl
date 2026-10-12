```@raw html
<h1 style="white-space:nowrap"><img src="./assets/mate-icon.png" alt="" width="31" height="31" style="display:inline-block;width:31px;height:31px;flex-shrink:0;vertical-align:middle;margin-right:0.35em">Mate73.jl</h1>
```

**This package reads and writes MATLAB `.mat` files of version 7.3. It uses only Julia code.
It does not use the HDF5 C library. It also works inside a small compiled program.**

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

## What this package covers

**It reads one file format only: the format built on HDF5.**

MATLAB has older formats, from version 4 to version 7. They use a different container. MAT.jl
already covers them in the Julia ecosystem. This package does not repeat that work.

Inside version 7.3 it reads numbers, true and false values, text, complex numbers and empty
arrays. It reads cell arrays, structs and objects. It writes numbers, true and false values,
text, structs and cell arrays, and it writes back a whole `Dict` that it or MAT.jl read. [The format](format.md) has the full list, and the list of what
it cannot do.

## Two ways to read

**Use the short way. Give the type only if you build a small compiled program.**

| | short way | with the type |
|---|---|---|
| whole file | `matread(path)` | — |
| one variable | `matread(f, "A")` | `matread(f, "A", Matrix{Float64})` |
| one variable, no handle | — | `matread(path, "A", Matrix{Float64})` |
| a field below a mark | `matread(f, ref)` | `matread(f, ref, "inner/values", Matrix{Float64})` |
| works in a small program | no | yes |

Give a path instead of an open file when you want one variable and nothing else. Open the
file first when you want several, so it is read once rather than once for each variable.

A mark is what a cell array gives you for each of its items. A path may start at one instead of
at the top of the file, which is how you reach a field of a struct held in a cell.

The short way works out the type from the file, as MAT.jl does. Use it in ordinary Julia code.

The long way exists for a tool named `juliac`. That tool builds a small program from Julia
code. Its option `--trim=safe` rejects any function that can return more than one type. A file
can hold many types. So the caller states the type instead.

Think of a parcel with no label. You must say what is inside before you open it.

A program that never calls the short way does not carry it. The build removes it. So the short
way costs nothing to a program that does not use it.

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

### Types from a template file: `@matstructs`

**Point the macro at one file, and every file shaped like it reads into concrete, nested types.**

Use it for a family of files that share one layout: one file per test run, per day of
measurements, or per run of a simulation. One of them is the template; the program then reads
all of them fully typed.

```julia
@matstructs Cfg "template.mat" "cfg"     # the types of one variable
@matstructs Run "template.mat"           # one field for every variable in the file

cfg = matread(matopen("today.mat"), "cfg", Cfg)
run = matread("today.mat", Run)
cfg.limits.hi
run.cfg.runs[2].name
```

The template is read while the code is compiled, and the struct definitions its shape implies
are written where the macro stands. At run time only the typed reads are left, so the program
works inside a small compiled program and never holds a `Dict{String,Any}`.

| in the template | the field type |
|---|---|
| a struct | a struct of its own, such as `CfgLimits` |
| a cell of structs of one shape, or a struct array | an array of one struct |
| a cell whose items share one type | an array of that type, such as `Matrix{String}` |
| a cell of mixed items | a `Tuple` of their types |
| a 1x1 number | the number, such as `Float64` |
| anything else | its own type, such as `Matrix{Float64}` |

To see or edit the definitions instead, `print(matstructs(matread("template.mat")["cfg"], :Cfg))`
writes the same code as text; `matstructs` also takes a `Dict` from MAT.jl or a nested
`NamedTuple`. `tostruct(Cfg, d)` converts a `Dict` or `NamedTuple` you already hold into those
types. From a `NamedTuple` it works inside a small compiled program; from a `Dict{String,Any}`
it cannot, since every value is `Any` until the program runs.


## What the check does

When you give the type, the package does 3 checks against the file:

- the kind of number, such as a whole number or a decimal number
- the width in bytes
- the sign, for whole numbers

If a check fails, the package stops with an error. It does not read the bytes as the wrong
type. This matters. A check on the width alone can read past the end of a smaller array. You
then get numbers that look real but are not.

Use [`matclass`](@ref) first if you do not know what is in the file. It gives
`MAT_UNSUPPORTED` for a type this package does not read. It does not stop with an error, so
you can look through a whole file safely.

## Reading several variables at once

**`@matload` gives you the short way and the fixed return type at the same time.**

### Why it exists

Look at the 2 ways again. Each one costs you something.

- `matread(f, "A")` is short. Its result type is not fixed, so a small compiled program
  cannot use it.
- `matread(f, "A", Matrix{Float64})` has a fixed type. You repeat the call for each variable,
  and the file name and the type sit far apart.

`@matload` removes the repetition and keeps the fixed type. You list the variables once. The
macro writes one normal typed read for each line. The types stay in the code it writes, so
nothing is worked out while the program runs.

Think of a shopping list. You write the list once at home. In the shop you collect the items
one by one. The list did not buy anything; it only saved you from remembering.

### Example 1: a few arrays

```julia
v = @matload "results.mat" begin
    A::Matrix{Float64}
    B::Array{Float64,3}
    flags::Matrix{Bool}
end

v.A
v.flags
```

You get a named tuple. Its type is known before the program runs.

### Example 2: a file you already opened

The first item is a path or an open file. A path is opened once for the whole block, however
many variables you list. Give an open file when you have one already, or when you want to look
at the file first with `matkeys` or `matclass`.

```julia
f = matopen("results.mat")
v = @matload f begin
    A::Matrix{Float64}
    flags::Matrix{Bool}
end
```

### Example 3: single numbers

A MATLAB scalar is a 1x1 array in the file. Ask for a plain number type and you get the
value, not the array.

```julia
v = @matload f begin
    n::Int64            # the value, such as 42
    gain::Float64
    count::Matrix{Int64}  # the 1x1 array, if you want it
end
```

If the variable holds more than one value, this stops with an error. It does not pick one.

### Example 4: fields of a struct

Use a path. Give the field the name you want in the result.

```julia
v = @matload f begin
    gain = "cfg/gain"::Float64
    mode = "cfg/mode"::String
end

v.gain
v.mode
```

### Example 5: properties of an object

An object works the same way as a struct.

```julia
v = @matload f begin
    label = "obj/Name"::String
    data  = "obj/DynamicData"::Float64
end
```

### Example 6: fields below a mark

A cell of structs gives you a mark for each struct. Give the macro the file and the mark, and
every path in the block starts there.

```julia
runs = matread(f, "runs", Matrix{MatRef})

v = @matload f, runs[1] begin
    count = "count"::Float64
    values = "inner/values"::Matrix{Float64}
end
```

The same read without the macro is [`matread(f, mark, path, T)`](@ref
matread(::Mate73.MatFile, ::Mate73.MatRef, ::String, ::Type)).

### Example 7: one variable, no block

```julia
v = @matload f A::Matrix{Float64}
v.A
```

### The two line forms

| you write | it reads |
|---|---|
| `name::Type` | the variable called `name` |
| `name = "a/path"::Type` | that path, under the name `name` |

### The three sources

The first item says where the paths in the block start.

| you write | it reads from |
|---|---|
| `@matload "results.mat" begin` | that file, opened once for the whole block |
| `@matload f begin` | a file you already opened |
| `@matload f, ref begin` | the object `ref` marks, inside `f` |

## Writing a result

**A named tuple becomes a struct. A tuple becomes a cell array. Both nest.**

Think of a filing cabinet and a row of pigeonholes. A drawer has a label on every folder
inside it, and you ask for a folder by name: that is a struct. A pigeonhole has only a number,
and each hole may hold something different: that is a cell array.

You give `matwrite` a name and a value for each variable:

| you give | MATLAB sees |
|---|---|
| an `Array` of numbers or `Bool` | an array of the matching type |
| one number or `Bool` | a 1x1 array |
| a `String` | text |
| a `NamedTuple` | a struct, one field per name |
| a `Tuple` | a cell array of one row |
| a `Dict` | a struct, one field per key |
| any other array, such as `Array{Any}` | a cell array of the same shape |

The last 2 rows are what `matread(path)` and MAT.jl give back. They cannot be used inside a
small compiled program, because the type of each value is found only while it runs.

### Example 1: one flat file

```julia
using Mate73

matwrite("out.mat", "A" => rand(4, 4), "flags" => [true, false], "label" => "run 3")
```

### Example 2: a result with structure

A named tuple holds the settings. A tuple holds one entry for each run, and the entries need
not match in type.

```julia
settings = (gain = 2.5, mode = "fast", limits = (1.0, 10.0))
runs = ([1.0 2.0 3.0], "second run failed", (name = "third", ok = true))

matwrite("run.mat", "cfg" => settings, "runs" => runs, "count" => 3)
```

The file then holds `cfg` as a struct of 3 fields, one of which is a cell array of 2 numbers.
It holds `runs` as a cell array of 3 items: an array, a piece of text, and a struct. Read
through MAT.jl, which goes through the HDF5 C library and shares no code with this package,
that is:

```julia
julia> MAT.matread("run.mat")["cfg"]
Dict{String, Any} with 3 entries:
  "mode"   => "fast"
  "gain"   => 2.5
  "limits" => Any[1.0 10.0]

julia> MAT.matread("run.mat")["runs"][3]
Dict{String, Any} with 2 entries:
  "name" => "third"
  "ok"   => true
```

A field of a struct may itself be a struct or a cell array. An item of a cell array may be
either as well. There is no limit to the depth.

### Example 3: build the variables in a loop

Nothing is written until the end, because the place of each variable in the file depends on
the size of every other one. So collect them first with [`MatWriter`](@ref Mate73.MatWriter).

```julia
w = MatWriter()
for (name, value) in results
    push!(w, name, value)
end
matwrite("out.mat", w)
```

### Example 4: write a result and read it back

Both halves state their types. So a small compiled program can write its result and read it
again, and neither step works anything out while it runs.

```julia
matwrite("out.mat", "gain" => 2.5, "count" => Int64(7), "label" => "run 3")

v = @matload "out.mat" begin
    gain::Float64
    count::Int64
    label::String
end

v.gain      # 2.5
v.label     # "run 3"
```

A struct reads back one field at a time, by path:

```julia
matwrite("run.mat", "cfg" => (gain = 2.5, mode = "fast"))

v = @matload "run.mat" begin
    gain = "cfg/gain"::Float64
    mode = "cfg/mode"::String
end
```

A cell array gives you one mark for each item, because the items may differ in type. You
follow one mark at a time:

```julia
matwrite("run.mat", "runs" => ([1.0 2.0], "second"))

f = matopen("run.mat")
items = matread(f, "runs", Matrix{MatRef})
matread(f, items[1], Matrix{Float64})   # [1.0 2.0]
matread(f, items[2], String)            # "second"
```

### Example 5: write back what you read

A whole file, read by this package or by MAT.jl, writes back as it is:

```julia
matwrite("copy.mat", matread("original.mat"))
matwrite("copy.mat", MAT.matread("original.mat"))
```

With MAT.jl loaded, its own types are written in a simpler form. A struct array becomes a cell
array of structs, a table becomes a struct with one field per column, and an object becomes a
struct of its properties. [The format](format.md#Writing-back-what-you-read) has the full list.

### What you cannot write

- An empty tuple. A cell of one row needs at least one item, so it stops with an error. An
  empty `Array{Any}` writes an empty cell.
- Complex numbers, `datetime` and `string`. This package reads all of these. It writes none
  of them yet.
- Struct arrays, tables and objects as themselves. They are written in the simpler form above.
- Sparse arrays as sparse. A sparse array is written as a full one.
- Compression. Every array is written in one block, so the file is larger than one MATLAB
  writes.

## Order of the dimensions

**You get the same array that MATLAB shows. Nothing is turned around. Nothing is copied to
reorder it.**

Two facts cancel each other:

- MATLAB and Julia both put the first dimension down the columns.
- The file keeps the list of dimensions in the opposite order.

So the package fills a Julia array in file order, under the reversed dimensions. The result
matches MATLAB.

## Which package to use

**Use MAT.jl. Use this package only if you need one of 2 things.**

Pick Mate73.jl when you need:

- no C library among your dependencies, or
- to read a `.mat` file inside a small compiled program.

For everything else, MAT.jl is the better tool.

| | MAT.jl | Mate73.jl |
|---|---|---|
| MATLAB versions | 4, 5, 6, 7 and 7.3 | 7.3 only |
| The HDF5 C library | needed | not used |
| `matread(path)` gives a `Dict` | yes | yes |
| `datetime`, `string` | full values | full values |
| `table`, `categorical` | full values | full values |
| function handles | the stored values | the stored values |
| sparse arrays | yes | no |
| works in a small compiled program | no | yes |

The two agree where they overlap. The tests here read files that MATLAB wrote, and compare
every value against MAT.jl.
