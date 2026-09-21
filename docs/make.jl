using Documenter
using DocumenterVitepress
using MATTE73

makedocs(;
    modules = [MATTE73],
    authors = "el-oso",
    sitename = "MATTE73.jl",
    format = DocumenterVitepress.MarkdownVitepress(;
        repo = "github.com/el-oso/MATTE73.jl",
        devbranch = "master",
        devurl = "dev",
    ),
    pages = [
        "Home" => "index.md",
        "The format" => "format.md",
        "Trimmed binaries" => "trim.md",
        "API" => "api.md",
    ],
    warnonly = [:missing_docs],
)

# Documenter's own deploydocs leaves a Vitepress build in the wrong place and the site 404s.
DocumenterVitepress.deploydocs(;
    repo = "github.com/el-oso/MATTE73.jl",
    target = joinpath(@__DIR__, "build"),
    branch = "gh-pages",
    devbranch = "master",
    push_preview = true,
)
