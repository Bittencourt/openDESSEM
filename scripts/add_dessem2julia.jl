#!/usr/bin/env julia
# Script to add DESSEM2Julia dependency

using Pkg
Pkg.add(url = "https://github.com/Bittencourt/DESSEM2Julia.git")
println("DESSEM2Julia added successfully!")
