using Dopri
using Compat
using Base.Test

# Determine pure Fortran results
path = splitdir(@__FILE__)[1]
deps = normpath(joinpath(path,"..","deps"))
cmd = setenv(`$deps/testrunner`, ["LD_LIBRARY_PATH=$deps"])
results = open(readlines, cmd, "r")
ind1 = 0
ind2 = 0
ind3 = 0
ind4 = 0
ind5 = 0
for (i, r) in enumerate(results)
    if ismatch(r"ind1", r)
        ind1 = i
    elseif ismatch(r"ind2", r)
        ind2 = i
    elseif ismatch(r"ind3", r)
        ind3 = i
    elseif ismatch(r"ind4", r)
        ind4 = i
    elseif ismatch(r"ind5", r)
        ind5 = i
    end
end
tf5 = Float64[]
yf5 = Array(Vector{Float64},0)
for i = 1:ind1-1
    v = float(split(results[i]))
    push!(tf5, v[1])
    push!(yf5, v[2:6])
end
tf8 = Float64[]
yf8 = Array(Vector{Float64},0)
for i = ind1+1:ind2-1
    v = float(split(results[i]))
    push!(tf8, v[1])
    push!(yf8, v[2:6])
end
tf5spc = Float64[]
yf5spc = Array(Vector{Float64},0)
for i = ind2+1:ind3-1
    v = float(split(results[i]))
    push!(tf5spc, v[1])
    push!(yf5spc, v[2:6])
end
tf8spc = Float64[]
yf8spc = Array(Vector{Float64},0)
for i = ind3+1:ind4-1
    v = float(split(results[i]))
    push!(tf8spc, v[1])
    push!(yf8spc, v[2:6])
end
tf5all = Float64[]
yf5all = Array(Vector{Float64},0)
for i = ind4+1:ind5-1
    v = float(split(results[i]))
    push!(tf5all, v[1])
    push!(yf5all, v[2:6])
end
tf8all = Float64[]
yf8all = Array(Vector{Float64},0)
for i = ind5+1:length(results)
    v = float(split(results[i]))
    push!(tf8all, v[1])
    push!(yf8all, v[2:6])
end

# Low-level interface
function newton(_n::Ptr{Int32}, _x::Ptr{Float64}, _y::Ptr{Float64}, _f::Ptr{Float64},
    _rpar::Ptr{Float64}, _ipar::Ptr{Int32})
    n = unsafe_load(_n, 1)
    y = pointer_to_array(_y, n)
    r = sqrt(y[1]*y[1]+y[2]*y[2]+y[3]*y[3])
    r3 = r*r*r
    unsafe_store!(_f, y[4], 1)
    unsafe_store!(_f, y[5], 2)
    unsafe_store!(_f, y[6], 3)
    unsafe_store!(_f, -mu*y[1]/r3, 4)
    unsafe_store!(_f, -mu*y[2]/r3, 5)
    unsafe_store!(_f, -mu*y[3]/r3, 6)
    return nothing
end

function solout(nr::Ptr{Int32}, xold::Ptr{Float64}, x::Ptr{Float64},
    _y::Ptr{Float64}, n::Ptr{Int32}, con::Ptr{Float64}, icomp::Ptr{Int32},
    nd::Ptr{Int32}, rpar::Ptr{Float64}, ipar::Ptr{Int32}, irtrn::Ptr{Int32},
    xout::Ptr{Float64})
    push!(tj, unsafe_load(x, 1))
    y = copy(pointer_to_array(_y, unsafe_load(n, 1)))
    push!(yj, y)
    return nothing
end

mu = 398600.4415
s0 = [-1814.0, -3708.0, 5153.0, 6.512, -4.229, -0.744]
y = copy(s0)
tp = 5402.582703094263
xend = tp
x = 0.0
idid = 0
rtol = fill(1e-6, 6)
atol = fill(1.4901161193847656e-8, 6)
itol = 0
iout = 1
lwork = 200
liwork = 100
work = zeros(Float64, lwork)
iwork = zeros(Int32, liwork)
rpar = zeros(Float64, 1)
ipar = zeros(Int32, 1)
n = 6
tj = Float64[]
yj = Array(Vector{Float64},0)
cnewton = cfunction(newton, Void, Dopri.fcnarg)
csolout = cfunction(solout, Void, Dopri.soloutarg)

ccall((:c_dopri5, Dopri.lib), Void, (Ptr{Int32}, Ptr{Void}, Ptr{Float64}, Ptr{Float64},
    Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Ptr{Int32},
    Ptr{Void}, Ptr{Int32}, Ptr{Float64}, Ptr{Int32}, Ptr{Int32},
    Ptr{Int32}, Ptr{Float64}, Ptr{Int32}, Ptr{Int32}), 
    &n, cnewton, &x, y, &xend, rtol, atol,
    &itol, csolout, &iout, work, &lwork, iwork,
    &liwork, rpar, ipar, &idid)

# Copy results
tj5 = copy(tj)
yj5 = copy(yj)

# Reinitialization
empty!(tj)
empty!(yj)
y = copy(s0)
x = 0.0
work = zeros(Float64, lwork)
iwork = zeros(Int32, liwork)

ccall((:c_dop853, Dopri.lib), Void, (Ptr{Int32}, Ptr{Void}, Ptr{Float64}, Ptr{Float64},
    Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Ptr{Int32},
    Ptr{Void}, Ptr{Int32}, Ptr{Float64}, Ptr{Int32}, Ptr{Int32},
    Ptr{Int32}, Ptr{Float64}, Ptr{Int32}, Ptr{Int32}), 
    &n, cnewton, &x, y, &xend, rtol, atol,
    &itol, csolout, &iout, work, &lwork, iwork,
    &liwork, rpar, ipar, &idid)

tj8 = copy(tj)
yj8 = copy(yj)

# The tolerance must not be too small due to the differences between
# OPENLIBM, used by Julia,  and the LIBM (e.g. system or Intel) used by Fortran
tol = 1e-5
@test length(tf5) == length(tj5)
for (a,b) in zip(tf5, tj5)
    @test_approx_eq_eps a b tol
end
for (vf, vj) in zip(yf5, yj5)
    for (a, b) in zip(vf, vj)
        @test_approx_eq_eps a b tol
    end
end

@test length(tf8) == length(tj8)
for (a,b) in zip(tf8, tj8)
    @test_approx_eq_eps a b tol
end
for (vf, vj) in zip(yf8, yj8)
    for (a, b) in zip(vf, vj)
        @test_approx_eq_eps a b tol
    end
end

# High-level interface
function newton!(f, t, y, p)
    r = sqrt(y[1]*y[1]+y[2]*y[2]+y[3]*y[3])
    r3 = r*r*r
    f[1] = y[4]
    f[2] = y[5]
    f[3] = y[6]
    f[4] = -p.mu*y[1]/r3
    f[5] = -p.mu*y[2]/r3
    f[6] = -p.mu*y[3]/r3    
end

type Params
    mu::Float64
    yout::Vector{Float64}
end
p = Params(mu, Float64[])
tspan = [0.0, tp]
tj5, yj5 = dopri5(newton!, s0, tspan, points=:all, params=p)
tj8, yj8 = dop853(newton!, s0, tspan, points=:all, params=p)
@test length(tf5) == length(tj5)
for (a,b) in zip(tf5, tj5)
    @test_approx_eq_eps a b tol
end
for (vf, vj) in zip(yf5, yj5)
    for (a, b) in zip(vf, vj)
        @test_approx_eq_eps a b tol
    end
end

@test length(tf8) == length(tj8)
for (a,b) in zip(tf8, tj8)
    @test_approx_eq_eps a b tol
end
for (vf, vj) in zip(yf8, yj8)
    for (a, b) in zip(vf, vj)
        @test_approx_eq_eps a b tol
    end
end

# Test dense output
tspan = collect(0.0:1.0:tp)
tj5spc, yj5spc = dopri5(newton!, s0, tspan, points=:specified, params=p)
tj8spc, yj8spc = dop853(newton!, s0, tspan, points=:specified, params=p)
@test length(tf5spc) == length(tj5spc)
for (a,b) in zip(tf5spc, tj5spc)
    @test_approx_eq_eps a b tol
end
for (vf, vj) in zip(yf5spc, yj5spc)
    for (a, b) in zip(vf, vj)
        @test_approx_eq_eps a b tol
    end
end

@test length(tf8spc) == length(tj8spc)
for (a,b) in zip(tf8spc, tj8spc)
    @test_approx_eq_eps a b tol
end
for (vf, vj) in zip(yf8spc, yj8spc)
    for (a, b) in zip(vf, vj)
        @test_approx_eq_eps a b tol
    end
end

tspan = push!(collect(0.0:1.0:tp), tp)
tj5all, yj5all = dopri5(newton!, s0, tspan, points=:all, params=p)
tj8all, yj8all = dop853(newton!, s0, tspan, points=:all, params=p)
@test length(tf5all) == length(tj5all)
for (a,b) in zip(tf5all, tj5all)
    @test_approx_eq_eps a b tol
end
for (vf, vj) in zip(yf5all, yj5all)
    for (a, b) in zip(vf, vj)
        @test_approx_eq_eps a b tol
    end
end

@test length(tf8all) == length(tj8all)
for (a,b) in zip(tf8all, tj8all)
    @test_approx_eq_eps a b tol
end
for (vf, vj) in zip(yf8all, yj8all)
    for (a, b) in zip(vf, vj)
        @test_approx_eq_eps a b tol
    end
end

# Test solout interface
function solout!(told, t, y, contd, params)
    if told < 5000 < t
        push!(params.yout, 5000.0)
        for i = 1:6
            push!(params.yout, contd(i, 5000))
        end
        return dopricode[:abort]
    else
        return dopricode[:nominal]
    end
end
tj5, yj5 = dopri5(newton!, s0, tspan, solout=solout!, params=p)
for (a,b) in zip([tf5spc[5001]; yf5spc[5001]], p.yout)
    @test_approx_eq_eps a b tol
end
p = Params(mu, Float64[])
tj8, yj8 = dop853(newton!, s0, tspan, solout=solout!, params=p)
for (a,b) in zip([tf8spc[5001]; yf8spc[5001]], p.yout)
    @test_approx_eq_eps a b tol
end

