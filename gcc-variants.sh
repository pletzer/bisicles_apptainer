# Compiler-flag variants for the gcc container, sourced by the build/bench jobs.
# Ordered from conservative to aggressive. All target AMD Genoa (znver4).
# Fortran always keeps -fPIC and -fallow-argument-mismatch (needed by Chombo).
FA="-fallow-argument-mismatch"
VARIANTS=(v0-default v1-O3-znver4 v2-O3-znver4-relaxedmath v3-Ofast-znver4 v4-Ofast-znver4-aggressive)
declare -A CXXF FCF
CXXF[v0-default]=""        # empty = container default (-fPIC -O2 / -fPIC -O3 -funroll-loops)
FCF[v0-default]=""
CXXF[v1-O3-znver4]="-fPIC -O3 -march=znver4"
FCF[v1-O3-znver4]="-fPIC -O3 -funroll-loops -march=znver4 $FA"
CXXF[v2-O3-znver4-relaxedmath]="-fPIC -O3 -march=znver4 -fno-math-errno -fno-trapping-math -fno-signed-zeros"
FCF[v2-O3-znver4-relaxedmath]="-fPIC -O3 -funroll-loops -march=znver4 -fno-math-errno -fno-trapping-math -fno-signed-zeros $FA"
CXXF[v3-Ofast-znver4]="-fPIC -Ofast -ffast-math -march=znver4"
FCF[v3-Ofast-znver4]="-fPIC -Ofast -ffast-math -funroll-loops -march=znver4 $FA"
CXXF[v4-Ofast-znver4-aggressive]="-fPIC -Ofast -ffast-math -march=znver4 -funroll-loops -fipa-pta -fprefetch-loop-arrays"
FCF[v4-Ofast-znver4-aggressive]="-fPIC -Ofast -ffast-math -funroll-loops -march=znver4 -fipa-pta -fprefetch-loop-arrays $FA"
