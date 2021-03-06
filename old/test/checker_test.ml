(* Dhruv Makwana *)
(* Old.Checker External Tests *)
(* These will be easier to write with a parser. *)

open Base
;;

open Vars
;;

module Ast =
  Old.Ast
;;

let check_expr = 
  Old.Checker.check_expr ~counter:1719
;;

let pretty x =
  Stdio.printf
    !"%{sexp: string Or_error.t}\n"
    (Or_error.map x ~f:(Ast.(string_of_pp pp_linear_t)))
;;

let arr : Ast.expression =
  Array_Intro (Int_Intro 5)
;;

let%expect_test "checker_unit_intro" =
  check_expr Unit_Intro
  |> pretty;
  [%expect {| (Ok I) |}]
;;

let%expect_test "checker_var_unbound" =
  check_expr (Var one)
  |> pretty;
  [%expect {| (Error "Unbound variable one_1 (not found in environment)") |}]
;;

let unit_elim : Ast.expression =
  Unit_Elim (Unit_Intro, arr)
;;

let%expect_test "checker_unit_elim" =
  check_expr unit_elim
  |> pretty;
  [%expect {| (Ok Arr[0]) |}]
;;

let pair : Ast.expression =
  Pair_Intro (arr, Unit_Intro)
;;

let%expect_test "checker_pair_intro" =
  check_expr pair
  |> pretty;
  [%expect {| (Ok "Arr[0] * I") |}]
;;

let pair_elim : Ast.expression =
  Pair_Elim (one, two, pair, Pair_Intro (Var two, Var one))
;;

let%expect_test "checker_pair_elim" = 
  check_expr pair_elim
  |> pretty;
  [%expect {| (Ok "I * Arr[0]") |}]
;;

let%expect_test "checker_pair_elim" = 
  check_expr (Pair_Elim (one, two, pair, Var one))
  |> pretty;
  [%expect {| (Error "Variable two_2 not used.") |}]
;;

let unit_lambda : Ast.expression =
  Lambda (one, Unit, Var one)
;;

let%expect_test "checker_lambda" =
  check_expr unit_lambda
  |> pretty;
  [%expect {| (Ok "I --o I") |}]
;;

let app : Ast.expression =
  App (unit_lambda, Unit_Intro)
;;

let%expect_test "checker_app" =
  check_expr app
  |> pretty;
  [%expect {| (Ok I) |}]
;;

let forall : Ast.expression =
  ForAll_frac_cap (one, Lambda (two, Array_t (Var one), Var two))
;;

let%expect_test "checker_forall" =
  check_expr forall
  |> pretty;
  [%expect {| (Ok "\226\136\128 one_1. Arr[one_1] --o Arr[one_1]") |}]
;;

let specialise : Ast.expression =
  Specialise_frac_cap(forall, Succ Zero)
;;

let%expect_test "checker_specialise" =
  check_expr specialise
  |> pretty;
  [%expect {| (Ok "Arr[1] --o Arr[1]") |}]
;;

let%expect_test "checker_specialise" =
  check_expr (Specialise_frac_cap(forall, Succ (Var three)))
  |> pretty;
  [%expect {|
    (Error
     "Specialise_frac_cap: (Succ (Var ((id 3) (name three)))) not found in environment.") |}]
;;

let%expect_test "checker_array_elim" =
  check_expr (Array_Elim (one, arr, Var one))
  |> pretty;
  [%expect {| (Ok Arr[0]) |}] 
;;

let prims : Ast.primitive list =
   (* Operators *)
  [ Split_Permission
  ; Merge_Permission
  ; Free
  ; Copy (* xCOPY *)
  ; Swap (* xSWAP *)

   (* Routines/Functions *)
  ; Sum_Mag (* xASUM *)
  ; Scalar_Mult_Then_Add (* xAXPY *)
  ; DotProd (* xDOT *)
  ; Norm2 (* xNRM2 *)
  ; Plane_Rotation (* xROT *)
  ; Givens_Rotation (* xROTG *)
  ; GivensMod_Rotation (* xROTM *)
  ; Gen_GivensMod_Rotation (* xROTMG *)
  ; Scalar_Mult (* xSCAL *)
  ; Index_of_Max_Abs (* IxAMAX *)
  ]
;;

let%expect_test "check_array_elim" =
  List.map ~f:(fun x -> check_expr (Primitive x)) prims
  |> List.iter ~f:pretty;
  [%expect {|
    (Ok
      "\226\136\128 split_perm_1719.\
     \n  Arr[split_perm_1719] --o Arr[split_perm_1719+1] * Arr[split_perm_1719+1]")
    (Ok
      "\226\136\128 merge_perm_1719.\
     \n  Arr[merge_perm_1719+1] * Arr[merge_perm_1719+1] --o Arr[merge_perm_1719]")
    (Ok "Arr[0] --o I")
    (Ok "\226\136\128 copy_1719. Arr[copy_1719] --o Arr[copy_1719] * Arr[0]")
    (Ok "Arr[0] * Arr[0] --o Arr[0] * Arr[0]")
    (Ok
     "\226\136\128 sum_mag_1719. Arr[sum_mag_1719] --o Arr[sum_mag_1719] * f64")
    (Ok
      "\226\136\128 sum_mag_vec_1719.\
     \n  f64 --o Arr[sum_mag_vec_1719] --o Arr[0] --o Arr[sum_mag_vec_1719] * Arr[0]")
    (Ok
      "\226\136\128 dot_prod_x_1719.\
     \n  Arr[dot_prod_x_1719] --o \226\136\128 dot_prod_y_1720.\
     \n    Arr[dot_prod_y_1720] --o\
     \n    ( Arr[dot_prod_x_1719] * Arr[dot_prod_y_1720] ) * f64")
    (Ok "\226\136\128 norm2_1719. Arr[norm2_1719] --o Arr[norm2_1719] * f64")
    (Ok "f64 --o f64 --o Arr[0] --o Arr[0] --o Arr[0] * Arr[0]")
    (Ok "f64 --o f64 --o ( f64 * f64 ) * ( f64 * f64 )")
    (Ok
      "Arr[0] --o Arr[0] --o \226\136\128 rotm_1719.\
     \n  Arr[rotm_1719] --o ( Arr[0] * Arr[0] ) * Arr[rotm_1719]")
    (Ok "f64 * f64 --o f64 * f64 --o ( f64 * f64 ) * ( f64 * Arr[0] )")
    (Ok "f64 --o Arr[0] --o Arr[0]")
    (Ok
      "\226\136\128 index_max_abs_1719.\
     \n  Arr[index_max_abs_1719] --o int * Arr[index_max_abs_1719]") |}]
;;
