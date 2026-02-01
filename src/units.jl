using Unitful: Unitful, NoUnits, uparse
using UnitfulAstro: UnitfulAstro
using UnitfulAngles: UnitfulAngles

const _UNIT_CONTEXT = [UnitfulAngles, UnitfulAstro, Unitful]


# ── Name mapping dicts ────────────────────────────────────────────────────────
# Each format maps format-specific unit names → Unitful-parseable names.

# Shared base: names that need remapping in all formats
const _BASE_NAME_DICT = Dict(
    "Angstroem" => "Å",    "Angstrom" => "Å",    "angstrom" => "Å",    "AA" => "Å",
    "solMass" => "Msun",    "solRad" => "Rsun",    "solLum" => "Lsun",
    "arcsec" => "arcsecond","arcmin" => "arcminute",
    "Ohm" => "Ω",
    "lyr" => "ly",
    "au" => "AU",
    "min" => "minute",      "h" => "hr",
)

# CDS-only additions
const _CDS_NAME_DICT = merge(_BASE_NAME_DICT, Dict(
    "jovMass" => "Mjup",    "geoMass" => "Mearth", "Mgeo" => "Mearth", "Rgeo" => "Rearth",
    "arcs" => "arcsecond",  "arcm" => "arcminute",
    "uarcsec" => "μas",     "marcsec" => "mas",
    "gauss" => "Gauss",
    "al" => "ly",
    "eps0" => "ε0",         "mu0" => "μ0",
    "a0" => "bohrRadius",
    "sec" => "s",
))

# VOUnit additions (IVOA VOUnits 1.1)
const _VOUNIT_NAME_DICT = merge(_BASE_NAME_DICT, Dict(
    "G" => "Gauss",         # VOUnit G = Gauss (deprecated); CDS G = gravitational constant (no remap needed)
    "a" => "yr",            # Julian year — Unitful a = Are (area)
))

# FITS additions (FITS Standard 4.0, Section 4.3)
const _FITS_NAME_DICT = merge(_BASE_NAME_DICT, Dict(
    "G" => "Gauss",         # same as VOUnit
    "a" => "yr",
))


# ── Regex helpers ─────────────────────────────────────────────────────────────

# Letter-only boundaries (not \b) since \b treats digits as word chars,
# so e.g. "10pix" has no \b between "10" and "pix".
# Alternation sorted longest-first so e.g. "arcsec" matches before "arcs".
_letter_boundary_re(alts) = Regex("(?<![a-zA-Z])(" * join(sort!(collect(alts), by=length, rev=true), "|") * ")(?![a-zA-Z])")

const _CDS_NAME_RE    = _letter_boundary_re(keys(_CDS_NAME_DICT))
const _VOUNIT_NAME_RE = _letter_boundary_re(keys(_VOUNIT_NAME_DICT))
const _FITS_NAME_RE   = _letter_boundary_re(keys(_FITS_NAME_DICT))


# ── Dimensionless unit sets ───────────────────────────────────────────────────
# Same across all formats: units with no Unitful equivalent → treated as "1".

const _DIMENSIONLESS = Set([
    "pix", "pixel", "ct", "count", "photon", "ph",
    "adu", "DN", "dn", "electron",
    "chan", "bin", "beam", "vox", "voxel",
    "bit", "byte",
])
# Matches a dimensionless unit + optional trailing power ([+-]?\d+),
# so that e.g. "beam-1" is replaced as a whole instead of leaving an orphaned "-1".
_sorted_dimless = sort!(collect(_DIMENSIONLESS), by=length, rev=true)
_dimless_alt = join(_sorted_dimless, "|")
# After a digit: "10pix" → keep digit, drop unit (10×1=10). Avoids "10"*"1"="101".
# (?!\.) in the power group prevents consuming digits before a decimal point (e.g. "pix0.1nm").
# (?![\da-zA-Z]) prevents matching when the unit is directly followed by a digit.
const _DIMLESS_AFTER_DIGIT = Regex("(\\d)(" * _dimless_alt * ")([+-]?\\d+(?!\\.))?(?![\\da-zA-Z])")
# Otherwise: replace with "1".
const _DIMLESS_RE = Regex("(?<![a-zA-Z])(" * _dimless_alt * ")([+-]?\\d+(?!\\.))?(?![\\da-zA-Z])")


# ── Shared pipeline ──────────────────────────────────────────────────────────
# All syntax transformations stacked; format-irrelevant ones are no-ops.

function _parse_unit(s::AbstractString, name_re, name_dict)
    s = strip(s)

    # Log notation: [unit] (CDS brackets) or log(unit) → exp10 transform
    m = match(r"^(?:\[(.+)\]|log\((.+)\))$", s)
    if m !== nothing
        s = string(something(m[1], m[2]))
        valuefn = exp10
    else
        valuefn = identity
    end

    # Dimensionless markers (CDS: "---"/"-", VOUnit/FITS: "unknown"/"UNKNOWN", empty)
    if s == "---" || s == "-" || s == "unknown" || s == "UNKNOWN" || isempty(s)
        return (; unit = NoUnits, valuefn)
    end

    # Percent: bare "%" or "20%" etc.
    s = replace(s, "%" => "*percent")
    startswith(s, '*') && (s = s[2:end])

    # CDS backslash-escaped constants: \h = Planck constant (must be before name dict)
    # PLANCKh placeholder has letters on both sides of "h", so the letter-boundary
    # regex won't match it during the name-dict pass.
    s = replace(s, r"\\h(?![a-zA-Z])" => "PLANCKh")

    # Format-specific name → Unitful name (single-pass via precompiled alternation regex)
    s = replace(s, name_re => m -> name_dict[m])

    # Restore Planck constant: PLANCKh → h (Unitful symbol for Planck constant)
    s = replace(s, "PLANCKh" => "h")

    # Factor × 10^exp: "1.5x10+11m" → "1.5e+11*m", "1.5×10+11/m" → "1.5e+11/m"
    m = match(r"^([\d.]+)[x×]10([+-]\d+)(.*)", s)
    if m !== nothing
        factor, exp, rest = string.(m.captures)
        sep = isempty(rest) || startswith(rest, '/') ? "" : "*"
        s = "$(factor)e$(exp)$(sep)$rest"
    else
        # Pure 10^exp prefix: "10+20cm-2" → "1e+20*cm-2", "10+20/m" → "1e+20/m"
        m = match(r"^10([+-]\d+)(.*)", s)
        if m !== nothing
            exp, rest = string.(m.captures)
            sep = isempty(rest) || startswith(rest, '/') ? "" : "*"
            s = "1e$(exp)$(sep)$rest"
        end
    end

    # Leading division: "/s" → "s^-1"
    startswith(s, "/") && (s = s[2:end] * "^-1")

    # ** → ^ (VOUnit/FITS power syntax; no-op for CDS which has no **)
    s = replace(s, "**" => "^")

    # Dot multiplication (only when letter on at least one side, preserving decimals)
    s = replace(s, r"\.(?=[a-zA-Z])" => "*")
    s = replace(s, r"(?<=[a-zA-Z])\." => "*")

    # Dimensionless units → replaced by 1 (pix, ct, photon, adu, etc.)
    # Done after dot→* so that e.g. "Jy.beam-1" is already "Jy*beam-1" and won't produce "1.1".
    s = replace(s, _DIMLESS_AFTER_DIGIT => s"\1")  # "10pix" → "10" (10×1=10)
    s = replace(s, _DIMLESS_RE => "1")              # "beam-1" → "1"

    # Bare-sign powers: "s-2" → "s^-2" (CDS; after ** already converted, this is a no-op for VOUnit/FITS)
    # Negative lookbehind for digit to skip 'e' in scientific notation like "1e+21"
    s = replace(s, r"(?<!\d)([a-zA-Z])([+-]\d+)" => s"\1^\2")

    # Unsigned powers: "m2" → "m^2" (letter+digit at end or before operator)
    s = replace(s, r"([a-zA-Z])(\d+)(?=$|[/*.)])" => s"\1^\2")

    try
        u = uparse(s; unit_context=_UNIT_CONTEXT)
        return (; unit = u, valuefn)
    catch
        @warn "Could not parse unit string" unit_string=s
        return (; unit = NoUnits, valuefn)
    end
end


# ── Public API ────────────────────────────────────────────────────────────────

"""
    cds(s) -> (; unit, valuefn)

Parse a CDS unit string (Standards for Astronomical Catalogues 2.0).
Used by VizieR catalogues, CDS/MRT ASCII tables, VOTable <= 1.3.

Returns a `NamedTuple` with:
- `unit`: a `Unitful.FreeUnits` object (`Unitful.NoUnits` for dimensionless or unparseable)
- `valuefn`: `identity` for regular units, `exp10` for dex/bracket units like `[K]`

# Examples
```julia
cds("km.s-1")   # (unit = km s⁻¹, valuefn = identity)
cds("[K]")       # (unit = K, valuefn = exp10)
cds("---")       # (unit = , valuefn = identity)
```
"""
cds(s::AbstractString) = _parse_unit(s, _CDS_NAME_RE, _CDS_NAME_DICT)

"""
    vounit(s) -> (; unit, valuefn)

Parse a VOUnit string (IVOA "Units in the VO" 1.1).
Used by VOTable >= 1.4 and modern VO services.

# Examples
```julia
vounit("m**-2")      # (unit = m⁻², valuefn = identity)
vounit("km.s**-1")   # (unit = km s⁻¹, valuefn = identity)
```
"""
vounit(s::AbstractString) = _parse_unit(s, _VOUNIT_NAME_RE, _VOUNIT_NAME_DICT)

"""
    fits(s) -> (; unit, valuefn)

Parse a FITS unit string (FITS Standard 4.0, Section 4.3).
Used by FITS file headers (BUNIT, TUNITn keywords).

# Examples
```julia
fits("erg.s**-1.cm**-2")  # (unit = erg s⁻¹ cm⁻², valuefn = identity)
```
"""
fits(s::AbstractString) = _parse_unit(s, _FITS_NAME_RE, _FITS_NAME_DICT)

# Deprecated alias
const cds_to_unitful = cds
