module Distributer.Configuration where

import Distributer.Examples
import Quipper.Printing

-- Path to the directory containing the hypergraph partitioning program
partDir = "./"

-- Partitioning parameters
algorithm = Patoh
subalgorithm = sea18
k = 5
epsilon = 0.03

-- Segmentation parameters
segmentWindow = 1000 :: Int
testWindow = segmentWindow `div` 5 
step = 1 + testWindow `div` 5
tolerance = 0.5 :: Rational

-- Set True to activate each extension, False to deactivate it
keepToffoli = False

-- The input circuit and its shape. Must be some of the cases from Examples.hs, listed below
circuit = qft 20
-- Show output (either Preview, to see the circuit, or GateCount, to see the stats):
outputAs = GateCount
{- List of available values for circuit:

-- From Quipper --
qft n -- where 'n' is the number of inputs (works fine up to 35)
bfWalk -- the quantum walk part of BooleanFormula, the other parts have a gate whose translation to Clifford+T is not supported by Quipper
bwt -- Binary Welded Tree
gse -- Ground State Estimation
usvR -- The algorithm first prepares a superposition of hypercubes, whose difference is the shortest vector. It then measures the output to collapse the state to a TwoPoint.

-- This one's partition is trivial:
usvH -- h_quantum from USV

-- The following should work, but take too much time due to the management of our data structures as lists (inefficient)
usvF -- f_quantum from USV
usvG -- g_quantum from USV

-- Additionally, these two don't work if bothRemotes is active, KaHyPart goes out of memory (more than 16GB)
tf  -- Triangle Finding problem 

-- Custom --
classical
classical2
subroutineCirc
simple
simple2
simple3
simple4
pull
pull1
pull2
interesting
interesting2
interesting3

-}

-- DO NOT CHANGE (aliases configuration) --

data PartAlg = Kahypar | Patoh

cutMetric = "kahypar/config/cut_rb_alenex16.ini" -- This should not be used
alenex17 = "kahypar/config/km1_direct_kway_alenex17.ini"
sea17 = "kahypar/config/km1_direct_kway_sea17.ini"
sea18 = "kahypar/config/km1_direct_kway_sea18.ini"
gecco18 = "kahypar/config/km1_direct_kway_gecco18.ini" -- Evolutionary Algorith,
