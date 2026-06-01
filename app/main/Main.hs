{-# LANGUAGE FlexibleContexts #-}
module Main where
import Control.Exception (bracket)
import qualified Data.Map as M
import qualified Data.IntMap as IM
import Data.List (sort, sortBy, nub, find)
import Numeric (showFFloat)
import System.Directory
import System.Environment
import GHC.IO.Handle (hDuplicate, hDuplicateTo)
import System.IO

import Quipper.Internal.Circuit
import Quipper.Internal.Generic
import Quipper.Internal.Printing
import Quipper.Libraries.QuipperASCIIParser

import Distributer.Common
import Distributer.Preparation
import Distributer.Partitioner
import Distributer.HGraphBuilder
import Distributer.DCircBuilder 
import Distributer.ColorPrinting

processArgs :: [String] -> (K, Size, InitSegSize, MaxHedgeDist, KeepCCZ, RunPreprocessing, PartAlg, PartDir, Format, Maybe FilePath, SaveTrace, Verbose)
processArgs []     = (-1, -1, 1000, 100, False, True, Kahypar, "./", GateCount, Nothing, False, True) -- Default values
processArgs (a:as) = case take 3 a of
    "--h" -> error $  "\n\n\nThis is a list of all available options. Use cat <circuit_file> | ./Main [options].\n"++
                      "\t -k= Distribute across given number of QPUs.\n"++
                      "\t -s= Each QPU has the given number of qbits.\n"++
                      "\t -w= Size of initial segments. Default: 1000.\n"++
                      "\t -cc Assume QPUs can execute CCZ gates.\n"++
                      "\t -np Skip internal preprocessing. Input must already satisfy the internal CZ gate-set contract.\n"++
                      "\t -o= Choose between different output formats: preview, eps, pdf, ascii. Default: gatecount.\n"++
                      "\t -f= Write the compiled new circuit to the given file in ASCII format.\n"++
                      "\t -vb Reduce output verbosity: omit partitioning progress.\n"++
                      "\t -d= Specifying root folder for KaHyPar.\n"++
                      "\n\n"
    "-k=" -> (read $ drop 3 a, s, w, m, kT, pp, alg, dir, o, outFile, sT, vb)
    "-s=" -> (k, read $ drop 3 a, w, m, kT, pp, alg, dir, o, outFile, sT, vb)
    "-w=" -> (k, s, read $ drop 3 a, m, kT, pp, alg, dir, o, outFile, sT, vb)
    "-m=" -> (k, s, w, read $ drop 3 a, kT, pp, alg, dir, o, outFile, sT, vb)
    "-cc" -> (k, s, w, m, True, pp, alg, dir, o, outFile, sT, vb)
    "-np" -> (k, s, w, m, kT, False, alg, dir, o, outFile, sT, vb)
    "-fp" -> (k, s, w, m, kT, pp, Patoh, dir, o, outFile, sT, vb)
    "-d=" -> (k, s, w, m, kT, pp, alg, drop 3 a, o, outFile, sT, vb)
    "-f=" -> (k, s, w, m, kT, pp, alg, dir, o, Just $ drop 3 a, sT, vb)
    "-o=" -> case find (\(tag,_) -> tag == drop 3 a) format_enum of
      Just f -> (k, s, w, m, kT, pp, alg, dir, snd f, outFile, sT, vb)
      Nothing -> error $ "Option "++a++" not recognised."
    "-st" -> (k, s, w, m, kT, pp, alg, dir, o, outFile, True, vb)
    "-vb" -> (k, s, w, m, kT, pp, alg, dir, o, outFile, sT, False)
    _     -> error $ "Option "++a++" not recognised."
  where
    (k,s,w,m,kT,pp,alg,dir,o,outFile,sT,vb) = processArgs as

prepareTempDirectory :: IO ()
prepareTempDirectory = do 
  dirExists <- doesDirectoryExist "temp"
  if dirExists then removeDirectoryRecursive "temp" else return ()
  createDirectory "temp"

parentDirectory :: FilePath -> Maybe FilePath
parentDirectory path = case dropWhile (/= '/') $ reverse path of
  [] -> Nothing
  (_:rest) -> Just $ reverse rest

writeCircuitASCII outputFile circuit shape = do
  case parentDirectory outputFile of
    Just dirPath -> createDirectoryIfMissing True dirPath
    Nothing -> return ()
  withFile outputFile WriteMode $ \handle ->
    bracket (hDuplicate stdout) restoreStdout $ \_ -> do
      hFlush stdout
      hDuplicateTo handle stdout
      print_generic ASCII circuit shape
      hFlush stdout
  where
    restoreStdout savedStdout = do
      hDuplicateTo savedStdout stdout
      hClose savedStdout

main :: IO ()
main = do
  args <- getArgs
  circASCII <- hGetContents stdin
  prepareTempDirectory
  let
    (cfg_k,cfg_s,cfg_initSegSize,cfg_maxHedgeDist,cfg_keepCCZ,cfg_runPreprocessing,cfg_partAlg,cfg_partDir,cfg_outputAs,cfg_compiledFile,cfg_saveTrace,cfg_verbose) = processArgs args
    (shape, input) = parse_circuit circASCII
    circ  = if cfg_runPreprocessing then prepareCircuit cfg_keepCCZ input shape else input
    (qin, ((ain,theGates,aout,nWires),namespace), qout) = encapsulate_generic id circ shape
    inputValidation = if cfg_runPreprocessing then Right () else validatePreprocessedInput theGates
    nQubits = cfg_k * cfg_s
    segments = partitioner (cfg_k, cfg_initSegSize, cfg_maxHedgeDist, cfg_partAlg, cfg_partDir, cfg_saveTrace, cfg_verbose) (nQubits,nWires) theGates
    gateCountInput = length theGates
    czsInput = length $ filter isCZ theGates
    (newGates, newWires, nEbits, nTeleports) = buildCircuit nWires (IM.size ain) segments
    newCircuit = unencapsulate_generic (qin, ((ain,newGates,aout,nWires+newWires),namespace), qout)
    printIt c s = case cfg_outputAs of
      Preview -> preview_withColor c s
      _ -> print_generic cfg_outputAs c s
    in if cfg_k < 2 || cfg_s < 1 
      then putStrLn "You must indicate the number of QPUs (k > 1) and their workspace qubit capacity (s > 0); example ./Main -k=2 -s=4" >> putStrLn "" 
      else if nQubits < nWires then putStrLn ("There are not enough qubits to run the circuit. Qubits required: "++show nWires++".") else case inputValidation of
        Left err -> error err
        Right () -> do
          case cfg_compiledFile of
            Just outputFile -> writeCircuitASCII outputFile newCircuit shape
            Nothing -> return ()
          putStrLn $ ""
          putStrLn $ "Original circuit:"
          printIt input shape
          if cfg_runPreprocessing then do
            putStrLn $ ""
            putStrLn $ "After preprocessing:"
            printIt circ shape
            else putStrLn $ "\nPreprocessing skipped (-np): input assumed to already satisfy the internal CZ gate-set contract."
          putStrLn $ ""
          putStrLn $ "New circuit:"
          printIt newCircuit shape
          putStrLn $ ""
          putStrLn $ "Original gate count: " ++ show gateCountInput
          putStrLn $ "Original CZ count: " ++ show czsInput
          putStrLn $ "Original qubit count: " ++ show nWires
          putStrLn $ ""
          putStrLn $ "Number of nonlocal CZs: " ++ (show $ countNonLocal segments)
          putStrLn $ "Number of ebits due nonlocal CZs: " ++ show nEbits
          putStrLn $ "Number of ebits due to teleportations: " ++ show nTeleports
          putStrLn $ "Total number of ebits: " ++ show (nEbits+nTeleports)
          putStrLn $ ""
          putStrLn $ "Preprocessing: " ++ if cfg_runPreprocessing then "enabled" else "skipped (-np)"
          case cfg_compiledFile of
            Just outputFile -> putStrLn $ "Compiled circuit file: " ++ outputFile
            Nothing -> return ()
          putStrLn $ "Extensions: " ++ case (cfg_runPreprocessing, cfg_keepCCZ) of
            (True,  True)  -> "KeepCCZ"
            (False, True)  -> "KeepCCZ ignored because preprocessing is skipped"
            _              -> "N/A"
          putStrLn $ "#QPUs = "++show cfg_k++"; QPU_size = "++show cfg_s
          putStrLn $ "initSegSize = "++show cfg_initSegSize++"; maxHedgeDist = "++show cfg_maxHedgeDist
