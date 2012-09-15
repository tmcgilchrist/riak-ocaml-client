open Riak
open Sys
open Unix
open OUnit

(* test fn for development *)
(*let client () =
  let conn = riak_connect "127.0.0.1" 8081 in
  let _ = match riak_ping conn with
    | true -> print_endline("Pong")
    | false -> print_endline("Bad response from server") in
  let (node,version) = riak_get_server_info conn in
  print_endline ("Node: " ^ node ^ ", Version: " ^ version);

  riak_disconnect conn;
  exit 0;;
  (* handle_unix_error client ();; *)
*)


let  (|>) x f = f x

let testbucket() =
  let i = int_of_float(Unix.time()) in
    Random.init i;
    let bucketnum = Random.int 999999999 in
    let tb = ("testbucket_" ^ string_of_int(bucketnum)) in
      tb;;

let setup _ =
  try
    let ip = Sys.getenv("RIAK_IP") in
    let port = int_of_string(Sys.getenv("RIAK_PORT")) in
      riak_connect ip port
  with Not_found ->
    riak_connect "127.0.0.1" 8081

let teardown _ =
  ()

let test_case_ping conn =
  let _ = match riak_ping conn with
    | true -> ()
    | false -> assert_failure("Can't connect to Riak") 
  in
  riak_disconnect conn

let test_case_ping_fail _ =
  ()

let test_case_invalid_network _ =
  ()


let test_case_server_info conn =
  let (node, version) = riak_get_server_info conn in
    assert_bool "Non empty node id" (node <> "");
    assert_bool "Non empty version #" (version <> "")

let test_case_client_id conn =
  let test_client_id = testbucket() in
  let _ = riak_set_client_id conn test_client_id in
  let client_id = riak_get_client_id conn in
    assert_equal test_client_id client_id

let show_option v =
  match v with
    | None -> print_endline "NONE"
    | Some x -> print_endline x

let test_case_put conn =
  let bucket = testbucket() in
  let rec putmany n =
    match n with
      | 0 -> ()
      | n ->
          let newkey = "foo" ^ string_of_int(n) in
          let newval = "bar" ^ string_of_int(n) in
          let objs =
            riak_put conn bucket (Some newkey)
              newval [Put_return_body true] None in
          let testval os =
            match os with
              | [] -> assert_failure "No objects returned from put"
              | o :: [] ->
                  (match o.obj_vclock with
                    | Some v -> assert_bool "Invalid vclock" (v <> "")
                    | None -> assert_failure
                          "Put with return_body didn't return any data")
              | o :: tl -> assert_failure "Put returned sublings"
          in
            testval objs;
            putmany (n-1)
  in
  let rec getmany n =
    match n with
      | 0 -> ()
      | n ->
          let getkey = "foo" ^ string_of_int(n) in
          let getval = "bar" ^ string_of_int(n) in
          let objs = riak_get conn bucket getkey [] in
            match objs with
              | [] -> assert_failure "No objects available to read"
              | o :: [] ->
                  (match o.obj_value with
                     | Some v ->
                         assert_equal v getval;
                         getmany (n-1)
                     | None -> assert_failure "Invalid value at key")
              | hd :: tl -> assert_failure "Sad panda"
  in
    putmany 1000;
    sleep(5);
    getmany 1000;;


let test_case_get conn =
  let bucket = testbucket() in
  let gt = "get_test" in
  let tv = "test_value" in
    riak_put conn bucket (Some gt) tv [] None |> ignore;
    let v = riak_get conn bucket gt [] in
    let asserts o =
      let v = o.obj_value in
        match v with
          | None -> assert_failure "Get value not found"
          | Some v -> assert_equal v tv
    in
      List.iter asserts v


let test_case_del conn =
  let bucket = testbucket() in
  let gt = "del_test" in
  let tv = "test_value" in
    riak_put conn bucket (Some gt) tv [] None |> ignore;
    sleep(1);
    riak_del conn bucket "del_test" [] |> ignore;
    let v = riak_get conn bucket gt [] in
     assert_equal (List.length v) 0


let test_case_list_buckets conn =
  let bucket = testbucket() in
  let gt = "bucket_test" in
  let tv = "test_value" in
    riak_put conn bucket (Some gt) tv [] None |> ignore;
    sleep(1);
    let buckets = riak_list_buckets conn in
      assert_bool "Buckets length > 0" (List.length buckets > 0);
      assert_bool "Find a specific bucket"
        (List.exists (function x -> x = bucket) buckets)

let test_case_list_keys conn =
  let bucket = testbucket() in
  let rec put_many num =
    match num with
      | 0 -> ()
      | n -> (let tk = "bucket_test" ^ string_of_int(n) in
              let tv = "test_value" in
                riak_put conn bucket (Some tk) tv [] None |> ignore;
                put_many (n-1))
  in
    put_many 66;
    let keys = riak_list_keys conn bucket in
      assert_equal 66 (List.length keys);
      assert_bool "Find a key"
        (List.exists (function x -> x = "bucket_test54") keys)

let test_case_get_bucket conn =
  let bucket = testbucket() in
  let gt = "bucket_test" in
  let tv = "test_value" in
    riak_put conn bucket (Some gt) tv [] None |> ignore;
    sleep(1);
    let (n, multi) = riak_get_bucket conn bucket in
      (match n with
        | Some nval -> assert_bool "Valid bucket n value" (nval > 0l)
        | None -> assert_failure "Unexpected default N value");
      (match multi with
        | Some multival -> assert_equal false multival
        | None -> assert_failure "Unexpected default multi value")

let test_case_set_bucket conn =
  let bucket = testbucket() in
  let gt = "bucket_test" in
  let tv = "test_value" in
    riak_put conn bucket (Some gt) tv [] None |> ignore;
    sleep(1);
    riak_set_bucket conn bucket (Some 2l) (Some true);
    sleep(1);
    let (n, multi) = riak_get_bucket conn bucket in
      (match n with
         | Some nval -> assert_equal 2l nval
         | None -> assert_failure "Unexpected N value");
      (match multi with
         | Some multival -> assert_equal true multival
         | None -> ());
      riak_set_bucket conn bucket (Some 1l) (None);
      sleep(1);
      let (n, multi) = riak_get_bucket conn bucket in
        (match n with
           | Some nval -> assert_equal 1l nval
           | None -> assert_failure "Unexpected N value");
        (match multi with
           | Some multival -> assert_equal true multival
           (* passing None doesn't overwrite the previous
           * value *)
           | None -> ())


(* TODO: MapReduce, Index, Search */


(* TODO: clean up test buckets when complete? *)
(* these don't all need to be bracketed *)
let suite = "Riak" >:::
[
  "test_case_ping" >:: (bracket setup test_case_ping teardown);
  "test_case_ping_fail" >:: (bracket setup test_case_ping_fail teardown);
  "test_case_invalid_network" >::
    (bracket setup test_case_invalid_network teardown);
  "test_case_client_id" >:: (bracket setup test_case_client_id teardown);
  "test_case_server_info" >:: (bracket setup test_case_server_info teardown);
  "test_case_put" >:: (bracket setup test_case_put teardown);
  "test_case_get" >:: (bracket setup test_case_get teardown);
  "test_case_del" >:: (bracket setup test_case_del teardown);
  "test_case_list_buckets" >:: (bracket setup test_case_list_buckets teardown);
  "test_case_list_keys" >:: (bracket setup test_case_list_keys teardown);
  "test_case_get_bucket" >:: (bracket setup test_case_get_bucket teardown);
  "test_case_set_bucket" >:: (bracket setup test_case_set_bucket teardown);
]

let _ = run_test_tt_main suite
