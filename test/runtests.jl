using TestItems
using TestItemRunner
@run_package_tests

# Self-contained file: header and data in one file, separated by --- / === delimiters.
# Source: astropy io/ascii/tests/data/cds.dat (ported from test_cds_header_from_readme.py)
@testitem "cds self-contained" begin

    t = AstroASCIITables.read_cds(joinpath(@__DIR__, "data/cds.dat"))
    @test length(t) == 1
    @test t.Index[1] == 1
    @test t.RAh[1] == 3
    @test t.RAs[1] ≈ 39.09
    @test strip(getproperty(t, Symbol("DE-"))[1]) == "+"
    @test ismissing(t.AK[1])    # column is nullable ("?"), field is blank in data
    @test t.Fit[1] ≈ 1.35
end

# Separate ReadMe + data file; ReadMe has multi-line descriptions and nullable columns.
@testitem "cds description" begin

    readme = joinpath(@__DIR__, "data/cds/description/ReadMe")
    data   = joinpath(@__DIR__, "data/cds/description/table.dat")
    t = AstroASCIITables.read_cds(data; readme)
    @test length(t) == 2
end

# ReadMe with two stacked "Byte-by-byte Description" lines sharing one column block.
@testitem "cds multi header" begin

    readme = joinpath(@__DIR__, "data/cds/multi/ReadMe")

    t1 = AstroASCIITables.read_cds(joinpath(@__DIR__, "data/cds/multi/lhs2065.dat"); readme)
    @test length(t1) == 18
    @test t1.Lambda[end] ≈ 6479.32
    @test strip(t1.Fnu[end]) == "0.285937"

    t2 = AstroASCIITables.read_cds(joinpath(@__DIR__, "data/cds/multi/lp944-20.dat"); readme)
    @test length(t2) == 18
    @test t2.Lambda[1] ≈ 6476.09
    @test strip(t2.Fnu[end]) == "0.489005"
end

# ReadMe where the filename entry uses a "*" glob pattern.
@testitem "cds glob header" begin

    readme = joinpath(@__DIR__, "data/cds/glob/ReadMe")
    t = AstroASCIITables.read_cds(joinpath(@__DIR__, "data/cds/glob/lmxbrefs.dat"); readme)
    @test length(t) == 291
    @test strip(t.Name[end]) == "J1914+0953"
    @test strip(t.BibCode[end-1]) == "2005A&A...432..235R"
end

# Real VizieR download: 15-row table with 18 columns; check specific Bmag values.
@testitem "vizier table1" begin

    readme = joinpath(@__DIR__, "data/vizier/ReadMe")
    t = AstroASCIITables.read_cds(joinpath(@__DIR__, "data/vizier/table1.dat"); readme)
    @test length(t) == 15
    @test length(propertynames(t)) == 18
    expected_Bmag = [14.79, 15.00, 14.80, 12.38, 12.36, 12.24, 13.75,
                     13.65, 13.41, 11.59, 11.68, 11.53, 13.92, 14.03, 14.18]
    @test collect(skipmissing(t.Bmag)) ≈ expected_Bmag
end

# Nullable columns: limit specifiers [min/max]?, order specifiers ?+=, no-whitespace ?text.
# Source: astropy io/ascii/tests/data/cds/null/ (ported from test_cds_ignore_nullable,
# test_cds_no_whitespace, test_cds_order)
@testitem "cds null" begin


    # ReadMe: tests [min/max]?, ]min/max[?, and ?=value sentinels
    readme = joinpath(@__DIR__, "data/cds/null/ReadMe")
    t = AstroASCIITables.read_cds(joinpath(@__DIR__, "data/cds/null/table.dat"); readme)
    @test length(t) == 2
    @test length(propertynames(t)) == 9
    @test strip(t.Cluster[1]) == "Cr110"
    @test t.Q[1] ≈ 0.289               # ?=-9.999 sentinel; this row is non-missing
    @test t.EW[1] ≈ 29.5               # ?=-9.9 sentinel; this row is non-missing

    # ReadMe1: adds order specifiers (?+=, ?-=, ?+) and no-whitespace ?text
    readme1 = joinpath(@__DIR__, "data/cds/null/ReadMe1")
    t1 = AstroASCIITables.read_cds(joinpath(@__DIR__, "data/cds/null/table1.dat"); readme=readme1)
    @test length(t1) == 2
    @test length(propertynames(t1)) == 10
    @test t1.Q[1] ≈ 0.325              # ?=-9.999 sentinel; this row is non-missing
    @test t1.EW[1] ≈ 58.0             # ?=-9.9 sentinel; this row is non-missing
end

# MRT (Machine-Readable Table) files: CDS derivative used for AAS journal submissions.
# Same Byte-by-byte column format, but with Title/Authors/Notes preamble.
# Source: astropy io/ascii/tests/data/cds_mrt_dashes.txt
@testitem "mrt dashes" begin

    t = AstroASCIITables.read_cds(joinpath(@__DIR__, "data/cds_mrt_dashes.txt"))
    @test length(t) == 8
    @test length(propertynames(t)) == 2
    @test strip(t.DefaultName[1]) == "Sun"
    @test getproperty(t, Symbol("#CompsOnThisRow"))[1] == 1
    @test strip(t.DefaultName[2]) == "--LP 704-15"
    @test getproperty(t, Symbol("#CompsOnThisRow"))[2] == 3
    @test strip(t.DefaultName[end]) == "G 129-47"
    @test getproperty(t, Symbol("#CompsOnThisRow"))[end] == 1
end

# Large MRT file with many columns, nullable fields, limit flags, and Notes section.
# Source: astropy io/ascii/tests/data/cds2.dat
@testitem "mrt large" begin

    t = AstroASCIITables.read_cds(joinpath(@__DIR__, "data/cds2.dat"))
    @test length(t) == 215
    @test length(propertynames(t)) == 29
    @test strip(t.SST[1]) == "041314.1+281910"
    @test strip(t.CName[1]) == "LkCa 1"
    @test getproperty(t, Symbol("3.6mag"))[1] ≈ 8.54
    @test strip(t.SST[end]) == "044642.6+245903"
    @test strip(t.CName[end]) == "RXJ04467+2459"
    # nullable columns produce missing where field is blank
    @test eltype(getproperty(t, Symbol("e_4.5mag"))) == Union{Missing, Float64}
    @test count(ismissing, getproperty(t, Symbol("e_4.5mag"))) == 26
    @test ismissing(getproperty(t, Symbol("e_70mag"))[end])
    @test ismissing(getproperty(t, Symbol("160mag"))[end])
end

@testitem "cds no data" begin

    t = AstroASCIITables.read_cds(joinpath(@__DIR__, "data/no_data_cds.dat"))
    @test length(t) == 0
    @test length(propertynames(t)) == 12   # same columns as cds.dat
end

@testitem "cds functional" begin
    # cdsFunctional.dat: F18.16/F20.17/E24.18 wide floats, VizieR pipe-separator format

    t = AstroASCIITables.read_cds(joinpath(@__DIR__, "data/cdsFunctional.dat"))
    @test length(t) == 1
    @test t.logTe[1] ≈ 3.85
    @test t.Mass[1] ≈ 0.24458909
end

@testitem "_" begin
    import Aqua
    Aqua.test_all(AstroASCIITables; ambiguities=false)
    Aqua.test_ambiguities(AstroASCIITables)

    import CompatHelperLocal as CHL
    CHL.@check()
end
