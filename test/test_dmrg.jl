using ITensorGPU
using ITensorMPS
using ITensors
using Random: Random
using Test: @test, @testset

function heisenberg(n)
  opsum = OpSum()
  for j in 1:(n - 1)
    opsum += 0.5, "S+", j, "S-", j + 1
    opsum += 0.5, "S-", j, "S+", j + 1
    opsum += "Sz", j, "Sz", j + 1
  end
  return opsum
end

@testset "Basic DMRG" begin
  @testset "Spin-one Heisenberg" begin
    N = 10
    sites = siteinds("S=1", N)
    H = cuMPO(MPO(heisenberg(N), sites))
    psi = randomCuMPS(sites)
    dmrg_kwargs = (;
      nsweeps=3, maxdim=[10, 20, 40], mindim=[1, 10], cutoff=1e-11, noise=1e-11
    )
    energy, psi = dmrg(H, psi; outputlevel=0, dmrg_kwargs...)
    @test energy < -12.0
  end

  @testset "Transverse field Ising" begin
    N = 32
    sites = siteinds("S=1/2", N)
    Random.seed!(432)
    psi0 = randomCuMPS(sites)
    opsum = OpSum()
    for j in 1:N
      j < N && add!(opsum, -1.0, "Sz", j, "Sz", j + 1)
      add!(opsum, -0.5, "Sx", j)
    end
    H = cuMPO(MPO(opsum, sites))
    dmrg_kwargs = (; nsweeps=5, maxdim=[10, 20], cutoff=1e-12, noise=1e-10)
    energy, psi = dmrg(H, psi0; outputlevel=0, dmrg_kwargs...)

    # Exact energy for transverse field Ising model
    # with open boundary conditions at criticality
    energy_exact = 0.25 - 0.25 / sin(π / (2 * (2 * N + 1)))
    @test abs((energy - energy_exact) / energy_exact) < 1e-2
  end

  @testset "DMRGObserver" begin
    device = cu
    n = 5
    s = siteinds("S=1/2", n)

    H = device(MPO(heisenberg(n), s))
    ψ0 = device(randomMPS(s))

    dmrg_params = (; nsweeps=4, maxdim=10, cutoff=1e-8, noise=1e-8, outputlevel=0)
    observer = DMRGObserver(["Z"], s; energy_tol=1e-4, minsweeps=10)
    E, ψ = dmrg(H, ψ0; observer=observer, dmrg_params...)
    @test expect(ψ, "Z") ≈ observer.measurements["Z"][end] rtol =
      10 * sqrt(eps(real(ITensors.scalartype(ψ0))))
    @test correlation_matrix(ψ, "Z", "Z") ≈ correlation_matrix(cpu(ψ), "Z", "Z")
  end
end
