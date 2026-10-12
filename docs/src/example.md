# Example: a folder of test runs

A test rig writes one file per run. Every file has the same layout: a label, the settings the
run used, a trace, and a list of checks. Here we read the whole folder into typed structs, with
no `Dict{String,Any}` anywhere.

## The files

In real use the rig wrote these. Here we write three of them ourselves.

```@example runs
using Mate73

mkpath("runs")
for (i, gain) in enumerate((1.5, 2.0, 2.5))
    matwrite(
        "runs/run_00$i.mat",
        "label" => "run $i",
        "cfg" => (gain = gain, mode = "fast", limits = (lo = 0.0, hi = 10.0)),
        "trace" => gain .* [1.0 2.0 3.0 4.0],
        "checks" => (
            (name = "offset", value = 0.1i, ok = true),
            (name = "noise", value = 0.4i, ok = i < 3),
        ),
    )
end
readdir("runs")
```

## The types

Point `@matstructs` at one of the files. It reads that file when the code is compiled and
defines one struct for the file and one for each struct inside it.

```@example runs
@matstructs Run "runs/run_001.mat"
nothing # hide
```

To see what it defined, `matstructs` gives the same code as text:

```@example runs
print(matstructs(matread("runs/run_001.mat"), :Run))
```

A 1x1 number became a `Float64` or a `Bool`, each struct became a type named after its place,
such as `RunCfgLimits`, and the cell of checks became a `Matrix{RunChecks}`, since a MATLAB
cell always has 2 dimensions.

## Reading the folder

Every file with the same layout now reads into `Run`:

```@example runs
function summarize(path::String)
    r = matread(path, Run)
    passed = count(c -> c.ok, r.checks)
    return (r.label, r.cfg.gain * r.cfg.limits.hi, maximum(r.trace), passed)
end

[summarize(joinpath("runs", f)) for f in readdir("runs")]
```

Every field has a concrete type, so the compiler knows the result of `summarize` before it runs:

```@example runs
Base.return_types(summarize, (String,))
```

That is also what lets `summarize` go into a small compiled program built with
`juliac --trim`; see [Trimmed binaries](trim.md).

## When a file does not match

A file with a different layout stops with an error that names the missing field, instead of
reading wrong data:

```@example runs
matwrite("other.mat", "label" => "other", "trace" => [1.0 2.0])
try
    matread("other.mat", Run)
catch e
    print(sprint(showerror, e))
end
```
