function SolitaryWaveWhithamGreenNaghdi3(mesh :: Mesh, param :: NamedTuple, guess :: Vector{Float64}; iterative = false :: Bool, verbose = true :: Bool, max_iter = 50, tol = 1e-14, q=1, GN = false)
        # A good guess for low velocities is
        #function sol(x,α)
        #	2*α*sech.(sqrt(3*2*α)/2*x).^2
        #end
        c = param.c
        ϵ = param.ϵ
        μ = param.μ

        k = mesh.k
        F₁ 	= tanh.(sqrt(μ)*abs.(k))./(sqrt(μ)*abs.(k))
        F₁[1] 	= 1
        F₀       = 1im * sqrt.(3*(1 ./F₁ .- 1)).*sign.(k)

        if GN == true
                F₀ = 1im * k ./ (1 .+ μ/3 * k.^2 ).^(1/4)
        end

        Π⅔ = abs.(k) .< maximum(k) * 4/3
        krasny(k) = (abs.(k).> 1e-32 ).*k
        krasny!(k) = k[abs.(k).< 1e-32 ].=0

        Dx       =  1im * mesh.k

        function dealias( v :: Vector{Float64} )
                real.(ifft(krasny(Π⅔.*fft(v))))
        end

        function proj( u :: Vector{Float64}, v :: Vector{Float64} )
            u-0*(v'*u)*v/(norm(v,2)^2)
        end

        function h( v :: Vector{Float64} )
                1 ./(1 .- ϵ*v)
        end

        function h( v :: Vector{Float64}, k )
                1 ./((1 .- ϵ*v).^k)
        end
        function ζ( v :: Vector{Float64} )
                v./(1 .- ϵ*v)
        end
        function Four( v )
                real.(ifft(F₀.*fft(v)))
        end

        function E( η :: Vector{Float64} , u :: Vector{Float64} )
                return η.^2 .+ (1 .+ ϵ*η).*(u.^2) .+ 1/3 .* ((1 .+ ϵ*η).^3).* (Four( u ).^2)
        end

        function F( v :: Vector{Float64} )
                return (-1/3 .* Four( h(v,3).* Four(v)) .+
                        ϵ/2 .*  h(v,4) .* (Four(v).^2) .+
                        h(v,2).* (v .- ϵ/2 .* v.^2) .-
                        1/(c^2) .* h(v,3).* v)/c^2
        end

        function Fabs( v :: Vector{Float64} )
                return (abs.(-1/3 .* Four( h(v,3).* Four(v))) .+
                        abs.(ϵ/2 .*  h(v,4) .* (Four(v).^2)) .+
                        abs.( h(v,2).*v) .+ abs.( ϵ/2 .* h(v,2).* v.^2) .+
                        1/(c^2) .* abs.(h(v,3).* v))/c^2
        end

        if iterative == false
                k = mesh.k
                x = mesh.x
                x₀ = mesh.x[1]
                FFT = exp.(-1im*k*(x.-x₀)');
                IFFT = exp.(1im*k*(x.-x₀)')/length(x);
                Id = Diagonal(ones(size(x)));
                M₀ = real.(IFFT*(Diagonal( F₀)*FFT))
                M(v) = Diagonal( v )
                function JacF( v :: Vector{Float64} )
                                return (-1/3 * M₀ * M(h(v,3) )* M₀ .-
                                ϵ * M₀ * M( h(v,4) .* (M₀*v) ) .+
                                 ϵ * M( h(v,4) .* (M₀*v) ) * M₀ .+
                                 2*ϵ^2 * M(  h(v,5) .* ((M₀ * v).^2) ) .+
                                 M(h(v,2) .*(1 .- ϵ* v).+ 2*ϵ.* h(v,3 ).*(v.- ϵ/2* v.^2)).-
                                 M(h(v,3 ) .+ 3*ϵ* v.* h(v,4 ))./(c^2))/c^2
                end
        else
                function JacFfast( v :: Vector{Float64} )
                        dF(φ) = (-1/3 .* Four( (h(v).^3).* Four( φ ) ) .-
                                ϵ .* Four( (h(v).^4).* φ .* Four( v ) ) .+
                                 ϵ .*( (h(v).^4) .*Four(v) .* Four( φ ) .+ 2 * ϵ.*φ.* (h(v).^5) .* Four(v).^2 ) .+
                                 (h(v).^2).* (φ.- ϵ* v.* φ) .+ 2*ϵ.*φ.* (h(v).^3).* (v.- ϵ/2* v.^2).-
                                 φ.* ((h(v).^3) .+ 3*ϵ* v.* (h(v).^4) )./(c^2))/c^2
                        return LinearMap(dF, length(v); issymmetric=true, ismutating=false)
                end
        end

        flag=0
        iter = 0
        err = 1
        u = dealias(guess./(1 .+ ϵ*guess)) # initial guess for iteration
        du = similar(F(u))
        fu = similar(F(u))
        dxu = similar(u)
        hist=[]
        for i in range(1, length=max_iter)
                dxu .= real.(ifft(Dx.*fft(u)))
                dxu ./= norm(dxu,2)
                fu .= F(dealias(u))
    	        err = norm(fu.*u,1)/sqrt(norm(E(ζ(u),c*u)/c^2,1))
                err = norm(fu,Inf)/norm(Fabs(u),Inf)
    		if err < tol
    			@info string("Converged : ",err,"\n")
    			break
    		elseif verbose == true
                        print(string("error at step ",i,": ",err,"\n"))
    		end
                if i == max_iter
                        flag=1
                        @warn  "The algorithm did not converge"
                end
                if iterative == false
                        du .= Symmetric(JacF(u).-dxu*dxu') \ fu
                else
                        (du,dhist) = gmres( JacFfast(u) , fu ; log = true, tol = 1e-5 )
                        push!(hist,dhist)
                end
    		u .-= dealias(q*du)
        end

        return (ζ(u),c*u,flag,hist)
end
