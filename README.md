# AstroTables.jl

Read ASCII table formats common in astronomy – CDS/VizieR and MRT for now.

## Usage

```julia
julia> using AstroTables

# just run read() on a table file:
julia> tbl = AstroTables.read("catalog.dat")
n-element StructArray(...) with columns (:Index, :RAh, :RAm, :RAs, ...)
...

# and get a Julian table – array of rows:
julia> row = tbl[1]

# dimensionless — no units applied
julia> row.Index
1

# unitful:
julia> row.RAh
3 hr

julia> row.RAs
39.09 s

julia> row.Fit
1.35 GM⊙

# nullable column
julia> row.AK
missing
```

For VizieR-style ASCII tables with separate ReadMe and data files:

```julia
tbl = read("table1.dat"; readme="ReadMe")
```

## Features

Supports both self-contained CDS files and separate ReadMe + data layouts, as well as MRT (Machine-Readable Table) file format. Nullable columns become `Union{Missing, T}`. Physical units are applied automatically via [Unitful.jl](https://github.com/PainterQubits/Unitful.jl), including scaled prefixes (`0.1nm`) and logarithmic notation (`[K]`). Returns a `StructArray` — a lightweight columnar table that is convenient to work with directly.

Parsing is compatible with and tested against astropy's `io.ascii.cds` test suite.
