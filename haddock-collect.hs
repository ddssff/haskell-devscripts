#!/usr/bin/runhaskell
{-# OPTIONS -Wall #-}

import Data.List
import Data.Char
import System.Environment
import System.FilePath
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BL8
import Codec.Compression.GZip

type URL = String

-- copy from hoogle/src/Recipe/Hackage.hs
haddockHacks :: [String] -> [String]
haddockHacks = map (unwords . map f . words) . filter (not . isPrefixOf "@version ")
    where
        f "::" = "::"
        f (':':xs) = "(:" ++ xs ++ ")"
        f ('!':'!':x:xs) | isAlpha x = xs
        f ('!':x:xs) | isAlpha x || x `elem` "[(" = x:xs
        f x | x `elem` ["[overlap","ok]","[incoherent]"] = ""
        f x = x

haddockPackageUrl :: URL -> [String] -> [String]
haddockPackageUrl x = concatMap f
    where f y | "@package " `isPrefixOf` y = ["@url " ++ x, y]
              | otherwise = [y]
-- copy end

filterHaddock :: URL -> String -> String
filterHaddock url = unlines . haddockHacks . haddockPackageUrl url . lines

readFileGz :: FilePath -> IO String
readFileGz file
  | takeExtension file == ".gz" = do
    c <- BL.readFile file
    return $ BL8.unpack . decompress $ c
  | otherwise = readFile file

readAndPrint :: URL -> FilePath -> FilePath -> IO ()
readAndPrint prefix outdir file = do
  f <- readFileGz file
  writeFile outfile $ filterHaddock url f
    where dropgz f | takeExtension f == ".gz" = dropExtension f
                   | otherwise                = f
          outfile = outdir </> takeFileName (dropgz file)
          url = prefix ++ dropFileName file

main :: IO ()
main = do
  [p, o] <- getArgs
  c <- getContents
  mapM_ (readAndPrint p o) (lines c)
