; Checked 64-bit multiplications that the wide-arithmetic feature lowers to instructions with two
; results. Each overflow check must read the high half of the product, not an original operand.
target datalayout = "e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-i128:128-n32:64-S128-ni:1:10:20"
target triple = "wasm32-unknown-wasip1"

define i64 @signed_product(i64 %a, i64 %b) {
entry:
  %result = tail call { i64, i1 } @llvm.smul.with.overflow.i64(i64 %a, i64 %b)
  %overflow = extractvalue { i64, i1 } %result, 1
  br i1 %overflow, label %trap, label %done

trap:
  tail call void @llvm.trap()
  unreachable

done:
  %product = extractvalue { i64, i1 } %result, 0
  ret i64 %product
}

define i64 @unsigned_product(i64 %a, i64 %b) {
entry:
  %result = tail call { i64, i1 } @llvm.umul.with.overflow.i64(i64 %a, i64 %b)
  %overflow = extractvalue { i64, i1 } %result, 1
  br i1 %overflow, label %trap, label %done

trap:
  tail call void @llvm.trap()
  unreachable

done:
  %product = extractvalue { i64, i1 } %result, 0
  ret i64 %product
}

declare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)
declare { i64, i1 } @llvm.umul.with.overflow.i64(i64, i64)
declare void @llvm.trap()
