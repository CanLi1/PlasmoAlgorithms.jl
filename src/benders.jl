using JuMP
using Gurobi
using Plasmo

function fix(var,value)
  ##Sets value for constraint variable
  setlowerbound(var,value)
  setupperbound(var,value)
end

function isChildNode(g::PlasmoGraph, n1::PlasmoNode, n2::PlasmoNode)
  ##Checks if n1 is a child node of n2
  for node in LightGraphs.out_neighbors(g.graph,getindex(g,n2))
    if (n1 == g.nodes[node]) return true
      return true
    end
  end
  return false
end

##Place MP and SP into PlasmoGraph
mp = Model(solver = GurobiSolver())
sp = Model(solver = GurobiSolver())

@variable(mp,y>=0)
@objective(mp,Min,2y)

@variable(sp,x[1:2]>=0)
@variable(sp,y>=0)
@constraint(sp,c1,2x[1]-x[2]+3y>=4)
@constraint(sp,x[1]+2x[2]+y>=3)
@objective(sp,Min,2x[1]+3x[2])

## Plasmo Graph
g = PlasmoGraph()
g.solver = GurobiSolver()
n1 = add_node(g)
setmodel(n1,mp)
n2 = add_node(g)
setmodel(n2,sp)

##Set n2 as a child node of n1
edge = Plasmo.add_edge(g,n1,n2)

## Linking constraints between MP and SP
@linkconstraint(g, n1[:y] == n2[:y])

function benderssolve(graph::PlasmoGraph;max_iterations=2)

  mpnode = graph.nodes[1]
  spnode = graph.nodes[2]

  mp = getmodel(mpnode)
  sp = getmodel(spnode)

  #TODO assume starts unbounded and add cut
  @variable(mp,θ>=0)
  mp.obj += θ

  solve(mp)
  
  for iter in 1:max_iterations 
    solve(mp)
    #Start iterating through the linking constraints
    links = getlinkconstraints(g)
    len = length(links)
    
    for j in 1:len
      #Iterate through each variable in the linked constraint
      for i in 1:length(links[j].terms.vars)
        var = links[j].terms.vars[i]

        #Determine which node the variable is associated with
        varnode = getnode(var)

        #Check if the variable is from the master node
        if isChildNode(g,spnode,varnode)
          #copy variable value and add dual constraint to sp
          val = getvalue(var)
          @variable(sp,val<=valbar<=val)
          if (getnode(links[j].terms.vars[i+1])==spnode)
              @constraint(sp,dual,valbar-links[j].terms.vars[i+1] == 0)
          elseif (getnode(links[j].terms.vars[i-1])==spnode)
              @constraint(sp,dual,valbar-links[j].terms.vars[i+1] == 0)
          end
          
          status = solve(sp)
          λ = getdual(dual)

          if status != :Optimal
            @constraint(mp, 0>=λ*(getupperbound(valbar)-var))
            println(mp)
          else
            θk = getobjectivevalue(sp)
            @constraint(mp,θ >= θk + λ*(getvalue(valbar)-var))
            println(mp)
          end
        end
      end
    end
    if getobjectivevalue(sp)==getvalue(θ)
      print(iter, " done")
      break
    else
      println(iter, " again")
    end
  end
end

benderssolve(g)
