-- | Left, right, and full outer joins.
--
-- The interface in this module is much nicer than the standard \"make
-- missing rows NULL\" interface that SQL provides.  If you really
-- want the standard interface then use "Opaleye.Join".

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Opaleye.FunctionalJoin where

import           Control.Applicative             ((<$>), (<*>))
import           Control.Arrow                   ((<<<))

import qualified Data.Profunctor.Product.Default as D
import qualified Data.Profunctor.Product         as PP

import qualified Opaleye.Column                  as C
import           Opaleye.Internal.Column         (Column, Nullable)
import qualified Opaleye.Internal.Join           as IJ
import qualified Opaleye.Internal.Operators      as IO
import qualified Opaleye.Internal.Unpackspec     as IU
import qualified Opaleye.Join                    as J
import qualified Opaleye.Select                  as S
import qualified Opaleye.SqlTypes                as T
import qualified Opaleye.Operators               as O
import           Opaleye.QueryArr                (Query)

joinF :: (columnsL -> columnsR -> columnsResult)
      -- ^ Calculate result columns from input columns
      -> (columnsL -> columnsR -> Column T.SqlBool)
      -- ^ Condition on which to join
      -> S.Select columnsL
      -- ^ Left query
      -> S.Select columnsR
      -- ^ Right query
      -> S.Select columnsResult
joinF f cond l r =
  fmap (uncurry f) (O.keepWhen (uncurry cond) <<< ((,) <$> l <*> r))

leftJoinF :: (D.Default IO.IfPP columnsResult columnsResult,
              D.Default IU.Unpackspec columnsL columnsL,
              D.Default IU.Unpackspec columnsR columnsR)
          => (columnsL -> columnsR -> columnsResult)
          -- ^ Calculate result row from input rows for rows in the
          -- right query satisfying the join condition
          -> (columnsL -> columnsResult)
          -- ^ Calculate result row from input row when there are /no/
          -- rows in the right query satisfying the join condition
          -> (columnsL -> columnsR -> Column T.SqlBool)
          -- ^ Condition on which to join
          -> S.Select columnsL
          -- ^ Left query
          -> S.Select columnsR
          -- ^ Right query
          -> S.Select columnsResult
leftJoinF f fL cond l r = fmap ret j
  where a1 = fmap (\x -> (x, T.sqlBool True))
        j  = J.leftJoinExplicit D.def
                                D.def
                                (PP.p2 (IJ.NullMaker id, nullmakerBool))
                                l
                                (a1 r)
                                (\(l', (r', _)) -> cond l' r')

        ret (lr, (rr, rc)) = O.ifThenElseMany (C.isNull rc) (fL lr) (f lr rr)

        nullmakerBool :: IJ.NullMaker (Column T.SqlBool)
                                      (Column (Nullable T.SqlBool))
        nullmakerBool = D.def

rightJoinF :: (D.Default IO.IfPP columnsResult columnsResult,
               D.Default IU.Unpackspec columnsL columnsL,
               D.Default IU.Unpackspec columnsR columnsR)
           => (columnsL -> columnsR -> columnsResult)
           -- ^ Calculate result row from input rows for rows in the
           -- left query satisfying the join condition
           -> (columnsR -> columnsResult)
           -- ^ Calculate result row from input row when there are /no/
           -- rows in the left query satisfying the join condition
           -> (columnsL -> columnsR -> Column T.SqlBool)
           -- ^ Condition on which to join
           -> S.Select columnsL
           -- ^ Left query
           -> S.Select columnsR
           -- ^ Right query
           -> S.Select columnsResult
rightJoinF f fR cond l r = fmap ret j
  where a1 = fmap (\x -> (x, T.sqlBool True))
        j  = J.rightJoinExplicit D.def
                                 D.def
                                 (PP.p2 (IJ.NullMaker id, nullmakerBool))
                                 (a1 l)
                                 r
                                 (\((l', _), r') -> cond l' r')

        ret ((lr, lc), rr) = O.ifThenElseMany (C.isNull lc) (fR rr) (f lr rr)

        nullmakerBool :: IJ.NullMaker (Column T.SqlBool)
                                      (Column (Nullable T.SqlBool))
        nullmakerBool = D.def

fullJoinF :: (D.Default IO.IfPP columnsResult columnsResult,
              D.Default IU.Unpackspec columnsL columnsL,
              D.Default IU.Unpackspec columnsR columnsR)
          => (columnsL -> columnsR -> columnsResult)
           -- ^ Calculate result row from input rows for rows in the
           -- left and right query satisfying the join condition
          -> (columnsL -> columnsResult)
           -- ^ Calculate result row from left input row when there
           -- are /no/ rows in the right query satisfying the join
           -- condition
          -> (columnsR -> columnsResult)
           -- ^ Calculate result row from right input row when there
           -- are /no/ rows in the left query satisfying the join
           -- condition
          -> (columnsL -> columnsR -> Column T.SqlBool)
          -- ^ Condition on which to join
          -> S.Select columnsL
          -- ^ Left query
          -> S.Select columnsR
          -- ^ Right query
          -> S.Select columnsResult
fullJoinF f fL fR cond l r = fmap ret j
  where a1 = fmap (\x -> (x, T.sqlBool True))
        j  = J.fullJoinExplicit D.def
                                D.def
                                (PP.p2 (IJ.NullMaker id, nullmakerBool))
                                (PP.p2 (IJ.NullMaker id, nullmakerBool))
                                (a1 l)
                                (a1 r)
                                (\((l', _), (r', _)) -> cond l' r')

        ret ((lr, lc), (rr, rc)) = O.ifThenElseMany (C.isNull lc)
                                     (fR rr)
                                     (O.ifThenElseMany (C.isNull rc)
                                        (fL lr)
                                        (f lr rr))

        nullmakerBool :: IJ.NullMaker (Column T.SqlBool)
                                      (Column (Nullable T.SqlBool))
        nullmakerBool = D.def
