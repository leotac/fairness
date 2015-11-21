using Gadfly, JuMP

#Empty glasses
function null_allocation(resource, capacity)
   alloc = [k => 0.0 for k in keys(capacity)]
end

#Greedy allocation
function greedy_allocation(resource, capacity)
   alloc = Dict() 
   for (cap,key) in sort([(cap,key) for (key,cap) in capacity],rev=true)
      alloc[key] = min(resource, cap)
      resource = max(0, resource - cap)
   end
   return alloc
end

#Maximin allocation
function maximin_allocation(resource, capacity)
   alloc = Dict()
   l = length(capacity)
   #make sure the minimum allocation is as large as possible 
   min_cap = minimum([cap for (key,cap) in capacity])
   min_alloc = min(min_cap, resource/l)
   for (key,v) in capacity
      alloc[key] = min_alloc
      resource -= min_alloc
   end
   #allocate the remaining resource greedily
   for (cap,key) in sort([(cap,key) for (key,cap) in capacity],rev=true)
      Δ = min(resource, cap - alloc[key])
      alloc[key] += Δ 
      resource -= Δ 
   end
   return alloc
end

#Max-min fair allocation
# Solved via the so-called water filling algorithm
function mmf_allocation(resource, capacity)
   residual_capacity = copy(capacity)
   alloc = [k => 0.0 for k in keys(residual_capacity)]
   #maximize the minimum allocation over the residual capacity
   while !isempty(residual_capacity) && resource > 0
      l = length(residual_capacity)
      min_cap = minimum([cap for (key,cap) in residual_capacity])
      Δ = min(min_cap, resource/l)
      for (key,v) in residual_capacity
         alloc[key] += Δ
         resource -= Δ
         residual_capacity[key] -= Δ
         #discard users with empty capacity
         residual_capacity[key] == 0 && delete!(residual_capacity, key)
      end
   end
   alloc
end

#Ratio-based fair allocation:
# Find a rate α such that
# αc₁ + αc₂ + αc₃ = b
# that is, α* = b / (c₁ + c₂ + c₃)
function concurrent_allocation(resource, capacity)
   α = resource / sum([cap for cap in values(capacity)])
   [k => α*capacity[k] for k in keys(capacity)]
end

#Proportional fairness:
# An allocation vector x is proportionally fair iff, for any other allocation vector,
# the sum of proportional changes (i.e., the change of the i-th allocation relative to the value 
# of the i-th allocation) is nonpositive. It is possible to show that the unique solution
# satisfying the condition can be found solving the following convex NLP:
# max ∑ log(x₁) + log(x₂) + log(x₃)
# s.t.
#     x₁ + x₂ + x₃ ≤ b
#     0 ≤ (x₁,x₂,x₃) ≤ (c₁,c₂,c₃)
function proportional_allocation(resource, capacity)
   m = Model()
   @defVar(m,x[keys(capacity)]≥0)
   @setNLObjective(m, :Max, sum{log(x[i]), i in keys(capacity)})
   @addConstraint(m, sum{x[i], i in keys(capacity)} ≤ resource)
   @addConstraint(m, bounds[i in keys(capacity)], x[i] ≤ capacity[i])
   solve(m)
   [k => getValue(x[k]) for k in keys(capacity)]
end

#Allocation minimizing Gini coefficient
function gini_allocation(resource, capacity)
   m = Model()
   I = keys(capacity)
   @defVar(m, x[I] ≥ 0)
   @defVar(m, y[I,I] ≥ 0)
   @setObjective(m, :Min, sum{(y[i,j]), i in I, j in I})
   @addConstraint(m, abs1[i in I, j in I], y[i,j] ≥ x[i] - x[j])
   @addConstraint(m, abs2[i in I, j in I], y[i,j] ≥ x[j] - x[i])
   @addConstraint(m, sum{x[i], i in I} == resource)
   @addConstraint(m, bounds[i in I], x[i] ≤ capacity[i])
   solve(m)
   [k => getValue(x[k]) for k in I]
end

#Allocation maximizing Jain's fairness index
# (minimize the inverse)
function jain_allocation(resource, capacity)
   m = Model()
   I = keys(capacity)
   @defVar(m,x[I]≥0)
   @setNLObjective(m, :Min, sum{x[i]^2, i in I})
   @addConstraint(m, sum{x[i], i in I} == resource)
   @addConstraint(m, bounds[i in I], x[i] ≤ capacity[i])
   solve(m)
   getValue(x)
end

#Egalitarian allocation: no-one is allowed to have more than the minimum!
function egalitarian_allocation(resource, capacity)
   #take the minimum capacity and use it for everyone
   min_cap = minimum([cap for (key,cap) in capacity])
   min_alloc = min(min_cap, resource/length(capacity))
   [k => min_alloc for k in keys(capacity)]
end

### Equality indices
jain_index(x) = sum(x)^2/(length(x)*sum(x.^2))
gini_index(x) = sum([abs(i - j) for i in x, j in x])/(2length(x)*sum(x))

### Plot
function plot_allocation(cap, alloc)
   l = length(alloc)
   sorted_keys = sort([keys(alloc)...])
   sorted_alloc = [alloc[k] for k in sorted_keys]
   sorted_res = [cap[k]-alloc[k] for k in sorted_keys]
   Gadfly.plot(x=[sorted_keys; sorted_keys], y=[sorted_res; sorted_alloc], color=[ones(l); zeros(l)], Geom.bar, Theme(default_color=colorant"orange",bar_spacing=10mm, grid_color=colorant"white", key_position=:none), Guide.xlabel(nothing), Guide.ylabel("beer [ml]"),Scale.color_discrete_manual(colorant"lightblue",colorant"orange"), Scale.y_continuous(minvalue=0, maxvalue=450, scalable=false))
end

## Run, plot and save figures
function run_and_plot()
   capacity = Dict{ASCIIString,Float64}("Alan" => 250, "Bill" => 450, "Carl" => 450)
   resource = 1000
   for (i,f) in enumerate([null_allocation, greedy_allocation, maximin_allocation, mmf_allocation, concurrent_allocation, proportional_allocation, egalitarian_allocation])
      Gadfly.draw(SVG("fig_$i.svg",4inch,3inch), plot_allocation(capacity, f(resource,capacity)))
   end
end

