(* Dhruv Makwana *)
(* LT4LA Typed AST *)
(* --------------- *)

open Base
;;

(* Utilities *)
let string_of_pp ?(size=80) f x =
  let buffer = Buffer.create size in
  f (Caml.Format.formatter_of_buffer buffer) x;
  Buffer.contents buffer
;;

(* Variables *)
type var =
  string
[@@deriving sexp_of,compare]
;;

include Comparator.Make(
  struct
    type t = var
    let compare = [%compare:var]
    let sexp_of_t = [%sexp_of:var]
  end)
;;

(* Fractional capabilities *)
type fc =
  | Z
  | S of fc
  | V of var
  | U of var
[@@deriving sexp_of]
;;

let (=) =
  [%compare.equal:var]
;;

let string_of_fc fc =
  let rec count acc = function
    | Z -> "z" :: acc
    | S fc -> count ("s" :: acc) fc
    | V var -> ("'" ^ var) :: acc
    | U var -> ("?" ^ var) :: acc in
  String.concat ~sep:" " @@ count [] fc
;;

let rec occurs_unify var = function
  | Z -> false
  | S fc -> occurs_unify var fc
  | V _ -> false
  | U var' -> String.(var = var')
;;

(* [equiv] is the minimal description of alpha-equivalent variables, that is if
   x ~ y then either (x,y) in [equiv] or (y,x) in [equiv] (but not both) *)
let rec same_fc equiv fc1 fc2 =
  let open Result.Let_syntax in
  match fc1, fc2 with

  | Z, Z ->
    return []

  | S fc1, S fc2 ->
    same_fc equiv fc1 fc2

  | Z, S _
  | S _, Z ->
    let pp () = string_of_fc in
    Result.failf "Could not show %a and %a are equal.\n\
                 Are you trying to write to/free an array or matrix before unsharing it?" pp fc1 pp fc2

  (* unification *)
  | (Z | V _ as fc), U var
  | U var, (Z | V _ as fc) ->
    return [(var, fc)]

  | S _ as fc, U var
  | U var, (S _ as fc) ->
    if occurs_unify var fc then
      Result.failf "Occurs check failed: ?%s found in %a.\n" var (Fn.const string_of_fc) fc
    else
      return [(var, fc)]

  | U var, U var' ->
    if String.(var = var') then
      Result.failf "Occurs check failed: ?%s found in ?%s.\n" var var'
    else
      return [(var, U var')]

  (* Variables *)
  | Z, V var
  | V var, Z
  | S _ , V var
  | V var, S _ ->
    if not (List.exists equiv ~f:(fun (x,y) -> x = var || y = var)) then
      return []
    else
      Result.failf
        "Var '%s is universally quantified.\n\
         Are you trying to write to/free/unshare an array or matrix you don't own?\n" var

  | V var1, V var2 ->
    if List.exists ~f:(fun (x,y) -> x = var1 && y = var2 || y = var1 && x = var2) equiv then
      return []
    else
      Result.failf "Could not show '%s and '%s and alpha-equivalent.\n" var1 var2
;;

(* Linear types *)
type lin =
  | Unit
  | Bool
  | Int
  | Elt
  | Arr of fc
  | Mat of fc
  | Pair of lin * lin
  | Bang of lin
  | Fun of lin * lin
  | All of var * lin
[@@deriving sexp_of]
;;

let pp_lin ppf =
  let open Caml.Format in
  let rec pp_lin ppf = function

    | Unit ->
      fprintf ppf "unit"

    | Bool ->
      fprintf ppf "bool"

    | Int ->
      fprintf ppf "int"

    | Elt ->
      fprintf ppf "float"

    | Bang lin ->
      let l, r = match lin with
        | Unit | Bool | Int | Elt | Bang _ -> "", ""
        | Pair _ | Arr _ | Mat _ | Fun _ | All _ -> "( ", " )" in
      fprintf ppf "!%s%a%s" l pp_lin lin r

    | Arr fc ->
      fprintf ppf "%s arr" @@ string_of_fc fc

    | Mat fc ->
      fprintf ppf "%s mat" @@ string_of_fc fc

    | Pair (fst, snd) ->
      let fl, fr = match fst with
        | Unit | Bool | Int | Elt | Bang _ | Arr _ | Mat _ -> "", ""
        | Pair _ | Fun _ | All _ -> "( ", " )"
      and sl, sr = match snd with
        | Unit | Bool | Int | Elt | Bang _ | Arr _ | Mat _ -> "", ""
        | Pair _ | Fun _ | All _ -> "( ", " )" in
      fprintf ppf "@[%s%a%s@ @[* %s%a%s@]@]" fl pp_lin fst fr sl pp_lin snd sr

    | Fun (arg, (Fun _ as res)) ->
      let al, ar = match arg with
        | Unit | Bool | Int | Elt | Bang _ | Arr _ | Mat _ | Pair _-> "",""
        | Fun _ | All _ -> "( ", " )" in
      fprintf ppf "@[%s%a%s --o@ %a@]" al pp_lin arg ar pp_lin res

    | Fun (arg, res) ->
      let al, ar = match arg with
        | Unit | Bool | Int | Elt | Bang _ | Arr _ | Mat _ | Pair _-> "",""
        | Fun _ | All _ -> "( ", " )" in
      fprintf ppf "%s%a%s@ --o@ %a" al pp_lin arg ar pp_lin res

    | All (var, (All _ as lin)) ->
      fprintf ppf "@ '%s. %a" var pp_lin lin

    | All (var, lin) ->
      fprintf ppf "'%s.@;<1 2>@[%a@]" var pp_lin lin in

  fprintf ppf "@[%a@]@?" pp_lin
;;

let rec substitute_in lin ~unify ~var ~replace =
  let rec loop = function
    | Z -> Z
    | S fc -> S (loop fc)
    | U var' | V var' as fc -> if var = var' then replace else fc in
  match lin with
  | Unit | Bool | Int | Elt as lin -> lin
  | Arr fc -> Arr (loop fc)
  | Mat fc -> Mat (loop fc)

  | Pair (fst, snd) ->
    Pair (substitute_in fst ~unify ~var ~replace,
          substitute_in snd ~unify ~var ~replace)

  | Bang lin ->
    Bang (substitute_in lin ~unify ~var ~replace)

  | Fun (arg, res) ->
    Fun (substitute_in arg ~unify ~var ~replace,
         substitute_in res ~unify ~var ~replace)

  | All (var', rest) as lin ->
    if not unify && var = var' then lin else All (var', substitute_in rest ~unify ~var ~replace)
;;

let substitute_unify lin ~var ~replace =
  substitute_in lin ~unify:true ~var ~replace
;;

let substitute_in lin ~var ~replace =
  substitute_in lin ~unify:false ~var ~replace
;;

(* Alpha-equivalence sucks *)
(* Think of this logic as joining two lines by the endpoints to form a trianlge.
   Case 1-2: if both endpoints are same (modulo flipping) then already in.
   Case 3-6: check if all pairs of endpoints match, and fill in missing edge.
   Case   7: neither endpoints match, so continue as before. *)
let add (x,y) equiv =
  let (=) = [%compare.equal : var] in
  let msg = "LT4LA: don't add" in
  try
    (x, y) :: List.fold_left equiv ~init:[] ~f:(fun rest (u,v) ->
      let rest = (u, v) :: rest in
      if u = x && v = y || u = y && v = x then
        failwith msg         (* ({u,v}={x,y}) + rest *)
      else if u = x then
        (y, v) :: rest       (* {x/u,v} + {x/u,y} + {y,v} + rest *)
      else if u = y then
        (x, v) :: rest       (* {y/u,v} + {x,y/u} + {x,v} + rest *)
      else if v = x then
        (u, y) :: rest       (* {u,x/v} + {x/v,y} + {y,u} + rest *)
      else if v = y then
        (u, x) :: rest       (* {u,v/y} + {x,v/y} + {u,x} + rest *)
      else
        rest)                (* {u,v} + {x,y} + rest *)
  with Failure msg' as exn ->
    if phys_equal msg msg' then equiv else raise exn
;;

(* Same lin UP TO alpha-equivalence *)
let rec same_lin equiv lin1 lin2 =
  let open Result.Let_syntax in
  let apply subs lin =
    List.fold subs ~init:lin ~f:(fun lin (var, fc) -> substitute_unify lin ~var ~replace:fc) in
  let to_string = string_of_pp pp_lin in

  match lin1, lin2 with
  | Unit, Unit
  | Bool, Bool
  | Int, Int
  | Elt, Elt ->
    return []

  | Bang lin1, Bang lin2 ->
    same_lin equiv lin1 lin2

  | Arr fc1, Arr fc2
  | Mat fc1, Mat fc2 ->
    same_fc equiv fc1 fc2

  | Pair (fst1, snd1) , Pair(fst2,snd2) ->
    let%bind subs1 = same_lin equiv fst1 fst2 in
    let%bind subs2 = same_lin equiv (apply subs1 snd1) (apply subs1 snd2) in
    return @@ subs1 @ subs2

  | Fun (arg1, body1) , Fun(arg2,body2) ->
    let%bind subs1 = same_lin equiv arg1 arg2 in
    let%bind subs2 = same_lin equiv (apply subs1 body1) (apply subs1 body2) in
    return @@ subs1 @ subs2

  | All (var1,lin1), All (var2,lin2) ->
    same_lin (add (var1, var2) equiv) lin1 lin2

  | _, _ ->
    let pp () x =
      to_string x
      |> String.split ~on:'\n'
      |> String.concat ~sep:"\n    " in
    Result.failf
      !"Specifically, could not show this equality:\n    %a\nwith\n    %a\n"
      pp lin1 pp lin2
;;

let same_lin equiv x y : (var * fc) list Or_error.t =
  Result.map_error
    (same_lin equiv x y)
    ~f:(fun err ->
       let pp () x =
         string_of_pp pp_lin x
         |> String.split ~on:'\n'
         |> String.concat ~sep:"\n    " in
       Error.of_string @@
       Printf.sprintf "Could not show equality:\n    %a\nwith\n    %a\n\n%s" pp x pp y err)
;;

(* Primitives *)
type arith =
  | Add
  | Sub
  | Mul
  | Div
  | Eq
  | Lt
[@@deriving sexp_of]
;;

let ariths =
  [ Add
  ; Sub
  ; Mul
  ; Div
  ; Eq
  ; Lt
  ]
;;

type prim =
  (* Boolean *)
  | Not_
  (* Arithmetic *)
  | IntOp of arith
  | EltOp of arith
  (* Arrays *)
  | Set
  | Get
  | Share
  | Unshare
  | Free
  (* Owl - no polymorphism so no Mapi :'( *)
  | Array
  | Copy
  | Sin
  | Hypot
  (* Level 1 BLAS *)
  | Asum
  | Axpy
  | Dot
  | Rotmg
  | Scal
  | Amax
  (* Matrix *)
  | Get_mat
  | Set_mat
  | Share_mat
  | Unshare_mat
  | Free_mat
  | Matrix
  | Eye
  | Copy_mat
  | Copy_mat_to
  | Size_mat
  | Transpose
  (* Level 3 BLAS/LAPACK *)
  | Symm
  | Gemm
  | Gesv
  | Posv
  | Posv_flip
  | Potrs
  | Syrk
[@@deriving sexp_of]
;;

let prims =
  (** Boolean *)
  [ Not_ ] @
  (** Arithmetic *)
  List.map ~f:(fun x -> IntOp x) ariths @
  List.map ~f:(fun x -> EltOp x) ariths @
  (* Arrays *)
  [ Set
  ; Get
  ; Share
  ; Unshare
  ; Free
  (* Owl - no polymorphism so no Mapi :'( *)
  ; Array
  ; Copy
  ; Sin
  ; Hypot
  (* Level 1 BLAS *)
  ; Asum
  ; Axpy
  ; Dot
  ; Rotmg
  ; Scal
  ; Amax
  (* Matrix *)
  ; Get_mat
  ; Set_mat
  ; Share_mat
  ; Unshare_mat
  ; Free_mat
  ; Matrix
  ; Eye
  ; Copy_mat
  ; Copy_mat_to
  ; Size_mat
  ; Transpose
  (* Level 3 BLAS/LAPACK *)
  ; Symm
  ; Gemm
  ; Gesv
  ; Posv
  ; Posv_flip
  ; Potrs
  ; Syrk
  ]
;;

let string_of_prim x =
  match sexp_of_prim x with
  | Sexp.Atom str ->
    String.lowercase str
  | Sexp.(List [Atom "IntOp"; Atom arith]) ->
    String.lowercase arith ^ "I"
  | Sexp.(List [Atom "EltOp"; Atom arith]) ->
    String.lowercase arith ^ "E"
  | _ ->
    assert false
;;

(* Expressions *)
type loc = Lexing.position = {
  pos_fname : string;
  pos_lnum : int;
  pos_bol : int;
  pos_cnum : int;
}
[@@deriving sexp_of]
;;

let dummy = {
  pos_fname = "dummy";
  pos_lnum = 0;
  pos_bol = 0;
  pos_cnum = 0;
}
;;

let line_col (loc : loc) =
  Int.(to_string loc.pos_lnum ^ ":" ^
       to_string @@ loc.pos_cnum - loc.pos_bol + 1)
;;

type exp =
  | Prim of loc sexp_opaque * prim
  | Var of loc sexp_opaque * var
  | Unit_I of loc sexp_opaque
  | True of loc sexp_opaque
  | False of loc sexp_opaque
  | Int_I of loc sexp_opaque * int
  | Elt_I of loc sexp_opaque * float
  | Pair_I of loc sexp_opaque * exp * exp
  | Bang_I of loc sexp_opaque * exp
  | Spc of loc sexp_opaque * exp * fc
  | App of loc sexp_opaque * exp * exp
  | Unit_E of loc sexp_opaque * exp * exp
  | Bang_E of loc sexp_opaque * var * exp * exp
  | Pair_E of loc sexp_opaque * var * var * exp * exp
  | Fix of loc sexp_opaque * var * var * lin * lin * exp
  | If of loc sexp_opaque * exp * exp * exp
  | Gen of loc sexp_opaque * var * exp
  | Lambda of loc sexp_opaque * var * lin * exp
  | Let of loc sexp_opaque * var * exp * exp
[@@deriving sexp_of]
;;

let loc = function
  | Prim (loc, _)
  | Var (loc, _)
  | Unit_I loc
  | True loc
  | False loc
  | Int_I (loc, _)
  | Elt_I (loc, _)
  | Pair_I (loc, _, _)
  | Bang_I (loc, _)
  | Spc (loc, _, _)
  | App (loc, _, _)
  | Unit_E (loc, _, _)
  | Bang_E (loc, _, _, _)
  | Pair_E (loc, _, _, _, _)
  | Fix (loc, _, _, _, _, _)
  | If (loc, _, _, _)
  | Gen (loc, _, _)
  | Lambda (loc, _, _, _)
  | Let (loc, _, _, _) -> loc
;;

let prec = function
  | Prim _ | Var _ | Unit_I _ | Pair_I _ -> 0
  | True _ | False _ | Int_I _ | Elt_I _ | Spc _ | App _ | Bang_I _ -> -1
  | Let _ | Unit_E _ | Bang_E _ | Pair_E _ | Fix _ | Gen _ | Lambda _ | If _ -> -2
;;

let rec is_value = function
  | Prim _ | Unit_I _ | True _ | False _ | Int_I _ | Elt_I _ | Var _ | Fix _ | Lambda _ -> true
  | App _ | Spc _ | Let _ | Unit_E _ | Bang_E _ | Pair_E _ | If _ -> false
  | Gen (_, _, exp) | Bang_I (_, exp) -> is_value exp
  | Pair_I (_, fst, snd) -> is_value fst && is_value snd
;;

let pp_exp ?(comments=false) ppf =
  let open Caml.Format in
  let parens exp ref = if prec exp > prec ref then "","" else "(", ")" in
  let string_of_lin = string_of_pp pp_lin in
  let rec pp_exp ppf = function

    | Prim (_, prim) ->
      fprintf ppf "Prim.%s" (string_of_prim prim)

    | Var (_, var) ->
      fprintf ppf "%s" var

    | Unit_I _ ->
      fprintf ppf "()"

    | True _ ->
      fprintf ppf "Many true"

    | False _ ->
      fprintf ppf "Many false"

    | Int_I (_, i) ->
      let l,r = if i < 0 then "(", ")" else "", "" in
      fprintf ppf "Many %s%d%s" l i r

    | Elt_I (_, e) ->
      let l,r = if Float.(e < 0.) then "(", ")" else "", "" in
      fprintf ppf "Many %s%F%s" l e r

    | Pair_I (_, exp1, exp2) ->
      fprintf ppf "@[(%a@ @[, %a)@]@]" pp_exp exp1 pp_exp exp2

    | Bang_I (_, exp) as bang ->
      let l,r = parens exp bang in
      fprintf ppf "Many %s%a%s" l pp_exp exp r

    | Spc (_, exp, fc) as spc ->
      if comments then
        let l, r = if prec exp >= prec spc then "","" else "(", ")" in
        fprintf ppf !"@[<2>%s%a%s@ (* [%{string_of_fc}] *)@]" l pp_exp exp r fc
      else
        fprintf ppf !"@[%a@]" pp_exp exp

    (* readability *)
    | App (loc, Lambda (_, var, _, body), exp) ->
      pp_exp ppf (Let (loc, var, exp, body))

    | App (_, fun_, arg) as app ->
      let fl, fr = if prec fun_ >= prec app then "","" else "(", ")"
      and al, ar = parens arg app in
      fprintf ppf "@[<2>%s%a%s@ %s%a%s@]" fl pp_exp fun_ fr al pp_exp arg ar

    (* readability *)
    | Let (_, var, Fix (_, f, x, _, _, exp), body)
      when var = f ->
      fprintf ppf !"@[@[<2>let rec %s %s =@ %a in@]@ %a@]"
        f x pp_exp exp pp_exp body

    | Let (_, var, exp, body) ->
      fprintf ppf !"@[@[<2>let %s =@ %a in@]@ %a@]"
        var pp_exp exp pp_exp body

    | Unit_E (_, exp, body) ->
      fprintf ppf !"@[@[<2>let () =@ %a in@]@ %a@]" pp_exp exp pp_exp body

    (* readability *)
    | Bang_E (_, var1, Var (_, var2),
              Bang_E (_, var3, Bang_I (_, Bang_I (_, Var (_, var4))), body))
      when var1 = var2 &&
           var3 = var4 &&
           var1 = var4 ->
      fprintf ppf "@[%a@]" pp_exp body

    (* readability *)
    | Bang_E (_, var1, exp,
              Bang_E (_, var2, Bang_I (_, Bang_I (_, Var (_, var3))), body))
      when var1 = var2 &&
           var2 = var3 ->
      fprintf ppf "@[@[<2>let %s =@ %a in@]@ %a@]" var1 pp_exp exp pp_exp body

    (* readability *)
    | Bang_E (loc, var, Bang_I(_, exp), body) ->
      pp_exp ppf (Let (loc, var, exp, body))

    | Bang_E (_, var, exp, body) ->
      fprintf ppf "@[@[<2>let Many %s =@ %a in@]@ %a@]" var pp_exp exp pp_exp body

    (* readability *)
    | Pair_E (_, var_a1, var_b, exp1, Pair_E (_, var_aa, var_ab, Var (_, var_a2), body))
      when var_a1 = var_a2 ->
      fprintf ppf "@[@[<2>let ((%s, %s), %s) =@ %a in@]@ %a@]"
        var_aa var_ab var_b pp_exp exp1 pp_exp body

    | Pair_E (_, var1, var2, exp1, exp2) ->
      fprintf ppf "@[@[<2>let (%s, %s) =@ %a in@]@ %a@]"
        var1 var2 pp_exp exp1 pp_exp exp2

    | Fix (_, f, x, _, _, body) ->
      fprintf ppf !"@[@[<2>let rec %s %s =@ %a in@]@ %s@]"
        f x pp_exp body f

    | If (_, cond, True _, False _) ->
      pp_exp ppf cond

    (* TODO revisit *)
    | If (_, cond, true_, False _) ->
      fprintf ppf "@[<hv>(@[%a@]@) && lazy (@[%a@])@]" pp_exp cond pp_exp true_

    (* TODO revisit *)
    | If (_, cond, True _, false_) ->
      fprintf ppf "@[<hv>(@[%a@]) || lazy (@[%a@])@]" pp_exp cond pp_exp false_

    (* TODO revisit *)
    | If (_, cond, true_, false_) ->
      fprintf ppf "@[<hv>if Prim.extract @;<1 3> (%a) then@;<1 2>@[%a@]@;else@;<1 2>@[%a@]@]"
        pp_exp cond pp_exp true_ pp_exp false_

    | Gen (_, var, (Gen _ | Lambda _ as exp)) ->
      if comments then
        fprintf ppf "@[(* ∀ %s *)@ %a@]" var pp_exp exp
      else
        fprintf ppf "@[%a@]" pp_exp exp

    | Gen (_, var, exp) ->
      if comments then
        fprintf ppf "@[<2>(* ∀ %s *)@ %a@]" var pp_exp exp
      else
        fprintf ppf "@[%a@]" pp_exp exp

    | Lambda (_, var, lin, (Lambda _ | Gen _ as exp)) ->
      if comments then
        fprintf ppf !"@[fun %s (* %{string_of_lin} *) ->@ %a@]" var lin pp_exp exp
      else
        fprintf ppf !"@[fun %s ->@ %a@]" var pp_exp exp

    | Lambda (_, var, lin, exp) ->
      if comments then
        fprintf ppf !"@[<2>fun %s (* %{string_of_lin} *) ->@ %a@]" var lin pp_exp exp
      else
        fprintf ppf !"@[<2>fun %s ->@ %a@]" var pp_exp exp

  in

  fprintf ppf "@[%a@]@?" pp_exp
;;

let%test_module "Test" =
  (module struct

    (* A stock of variables *)
    let one, two, three, four, five =
      ( "one", "two", "three", "four", "five" )
    ;;

    (* same_fc/string_of_fc *)
    let%expect_test "same_fc" =
      same_fc [] Z (S Z)
      |> Stdio.printf !"%{sexp:((var * fc) list,string)Result.t}";
      [%expect {|
        (Error
          "Could not show z and z s are equal.\
         \nAre you trying to write to/free an array or matrix before unsharing it?") |}]
    ;;

    let%expect_test "same_fc" =
      same_fc [] (S (S (V one))) (V one)
      |> Stdio.printf !"%{sexp:((var * fc) list,string)Result.t}";
      [%expect {| (Ok ()) |}]
    ;;

    let%expect_test "same_fc" =
      same_fc [(one,one)] (S (S (V one))) (V one)
      |> Stdio.printf !"%{sexp:((var * fc) list,string)Result.t}";
      [%expect {|
        (Error
          "Var 'one is universally quantified.\
         \nAre you trying to write to/free/unshare an array or matrix you don't own?\
         \n") |}]
    ;;

    let%expect_test "same_fc" =
      same_fc [] (V one) (S (S (V three)))
      |> Stdio.printf !"%{sexp:((var * fc) list,string)Result.t}";
      [%expect {| (Ok ()) |}]
    ;;

    let%expect_test "add" =
      let show x = Stdio.printf !"%{sexp: (var * var) list}\n" x in
      let it = add (one, two) []  in show it;
      let it = add (three, four) it in show it;
      let it = add (four, five) it in show it;
      let it = add (four, five) it in show it;
      [%expect {|
        ((one two))
        ((three four) (one two))
        ((four five) (one two) (three five) (three four))
        ((four five) (one two) (three five) (three four)) |}]
    ;;

  end)
;;
