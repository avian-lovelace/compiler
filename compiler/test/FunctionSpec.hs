module FunctionSpec
  ( testFunctions,
  )
where

import Core.Errors
import EndToEnd
import Test.Hspec

testFunctions :: Spec
testFunctions = do
  describe "Functions:" $ do
    it "Functions can be created and called" $
      "let foo = []: Int -> 5; print foo[];" `runsSuccessfullyWithOutput` "5\n"
    it "Functions can have parameters" $
      "let foo = [x: Int]: Int -> x * 2; print foo[10];" `runsSuccessfullyWithOutput` "20\n"
    it "Functions can have multiple parameters" $
      "let foo = [x: Int, y: Int, z: Int]: Int -> x - y * z; print foo[10, 3, 4];" `runsSuccessfullyWithOutput` "-2\n"
    it "Functions can execute statements" $
      "let foo = [x: Int]: Nil -> { print x; }; foo[1]; foo[2]; foo[3];" `runsSuccessfullyWithOutput` "1\n2\n3\n"
    it "Functions can use return statements to return values" $
      "let foo = [x: Int]: Int -> { print x; return x + 1; }; let result = foo[1]; print result;" `runsSuccessfullyWithOutput` "1\n2\n"
    it "Functions can use return statements to return early" $
      "let foo = [x: Int]: Int -> { if x < 0 then { return x; }; print 2 * x; return x + 1; }; print foo[-5]; print foo[3];" `runsSuccessfullyWithOutput` "-5\n6\n4\n"
    it "Return statements without an argument return nil" $
      "let foo = [x: Int]: Nil -> { if x < 0 then { return; }; print x; }; print foo[-5]; print foo[3];" `runsSuccessfullyWithOutput` "nil\n3\nnil\n"
    it "Functions can return functions" $
      "let foo = []: ([Int] -> Int) -> [x: Int]: Int -> x + 1; print foo[][5];" `runsSuccessfullyWithOutput` "6\n"
    it "Functions can capture parameters of outer functions" $
      "let foo = [x: Int]: ([Int] -> Int) -> [y: Int]: Int -> x * y; print foo[3][5];" `runsSuccessfullyWithOutput` "15\n"
    it "Functions can capture variable values" $
      "let cap = 3; let foo = []: Nil -> { print cap; }; foo[];" `runsSuccessfullyWithOutput` "3\n"
    it "The value of a captured variable is its value when it was captured, even if it changes later" $
      "let mut cap = 3; let foo = []: Nil -> { print cap; }; mut cap = 5; foo[];" `runsSuccessfullyWithOutput` "3\n"
    it "Captured variables can be used, even if the original variable no longer exists" $
      "let foo = []: ([] -> Int) -> { let cap = 3; return []: Int -> cap; }; print foo[][];" `runsSuccessfullyWithOutput` "3\n"
    it "When calling a function call expression, first the function expression is evaluated, then the arguments left-to-right, then the function call happens" $
      "let foo = []: ([Nil, Nil] -> Nil) -> { print 1; return [x: Nil, y: Nil]: Nil -> { print 4; }; }; foo[][{print 2;}, {print 3;}];" `runsSuccessfullyWithOutput` "1\n2\n3\n4\n"
    it "Functions bodies can shadow variables" $
      "let x = 1; let foo = []: Nil -> { let x = 2; print x; }; print x; foo[];" `runsSuccessfullyWithOutput` "1\n2\n"
    it "Functions bodies can shadow variables from before they are declared in a scope" $
      "let foo = []: Nil -> { let x = 2; print x; }; let x = 1; print x; foo[];" `runsSuccessfullyWithOutput` "1\n2\n"
  describe "Function statements:" $ do
    it "Functions can be created as statements and called" $
      "func foo = []: Int -> 5; print foo[];" `runsSuccessfullyWithOutput` "5\n"
    it "Functions defined by statement can be used in their scope before their definition" $
      "print foo[]; func foo = []: Int -> 5;" `runsSuccessfullyWithOutput` "5\n"
    it "Functions defined by statement can call other functions defined by statement" $
      "foo[4]; func foo = [x: Int]: Nil -> { print plusOne[x]; }; func  plusOne = [x: Int]: Int -> x + 1;" `runsSuccessfullyWithOutput` "5\n"
    it "A function defined by statement can call itself" $
      "print fib[4]; func fib = [x: Int]: Int -> if x <= 1 then x else fib[x - 1] + fib[x - 2];" `runsSuccessfullyWithOutput` "3\n"
    it "Functions defined by statement can call each other cyclically" $
      "foo[4]; func foo = [x: Int]: Nil -> { if x == 0 then { return; }; print \"foo\"; bar[x - 1]; }; func bar = [x: Int]: Nil -> { if x == 0 then { return; }; print \"bar\"; foo[x - 1]; };" `runsSuccessfullyWithOutput` "foo\nbar\nfoo\nbar\n"
    it "Functions defined by statement can capture variables" $
      "let cap = 5; print foo[]; func foo = []: Int -> cap;" `runsSuccessfullyWithOutput` "5\n"
    it "Functions defined by statement can capture variables defined later in scope, as long as they are defined by the first function call" $
      "func foo = []: Int -> cap; let cap = 5; print foo[];" `runsSuccessfullyWithOutput` "5\n"
    it "Variables captured by a function statement have their captured values set when the function is referenced" $
      "let mut cap = 1; printCap[]; mut cap = 2; printCap[]; func printCap = []: Nil -> { print cap; };" `runsSuccessfullyWithOutput` "1\n2\n"
    it "Variables can be transitively captured in function statements by inner function expressions" $
      "let cap = 1; foo[][]; func foo = []: ([] -> Nil) -> []: Nil -> { print cap; };" `runsSuccessfullyWithOutput` "1\n"
    it "Variables can be transitively captured in function statements by calling other function statements" $
      "let cap = 1; foo[]; func foo = []: Nil -> bar[]; func bar = []: Nil -> { print cap; };" `runsSuccessfullyWithOutput` "1\n"
    it "Functions defined by statement that call each other cyclically can capture variables transitively" $
      "let fooCap = \"foo\"; let barCap = \"bar\"; foo[4]; func foo = [x: Int]: Nil -> { if x == 0 then { return; }; print fooCap; bar[x - 1]; }; func bar = [x: Int]: Nil -> { if x == 0 then { return; }; print barCap; foo[x - 1]; };" `runsSuccessfullyWithOutput` "foo\nbar\nfoo\nbar\n"
  describe "Function errors:" $ do
    it "Functions cannot have multiple parameters with the same name" $
      "let foo = [x, y, x] -> x + y + x;" `failsToCompileWithError` conflictingParameterNamesError
    it "Functions parameters cannot shadow a variable in its declaration" $
      "let foo = [foo] -> 5;" `failsToCompileWithError` variableShadowedInDeclarationError
    it "Functions parameters cannot be mutated" $
      "let foo = [x] -> {mut x = x + 1;};" `failsToCompileWithError` mutatedParameterError
    it "Variables captured by a function cannot be mutated" $
      "let mut cap = 10; let foo = []: Nil -> {mut cap = 0;};" `failsToCompileWithError` mutatedCapturedIdentifierError
    it "Variables captured by a function cannot be mutated even after they are referenced" $
      "let mut cap = 10; let foo = []: Nil -> {print cap; mut cap = 0;};" `failsToCompileWithError` mutatedCapturedIdentifierError
    it "Functions must have type annotations on all parameters" $
      "let foo = [x]: Int -> x + 1;" `failsToCompileWithError` functionMissingParameterTypeAnnotation
    it "Functions must have return type annotations" $
      "let foo = [x: Int] -> x + 1;" `failsToCompileWithError` functionMissingReturnTypeAnnotation
    it "Return statement values in a function must match the function return type" $
      "let foo = []: Char -> { return 5; };" `failsToCompileWithError` typeExpectationError
    it "If a function body never returns, its type must match the return type" $
      "let foo = []: Nil -> 5;" `failsToCompileWithError` typeExpectationError
    it "If a function body only sometimes returns, its type must match the return type" $
      "let foo = [x: Bool]: Int -> { if x then { return 0; }; };" `failsToCompileWithError` functionBodyTypeError
    it "Return statements not in a function must return Nil" $
      "let foo = 5; return foo;" `failsToCompileWithError` typeExpectationError
    it "Non-function values cannot be called" $
      "let foo = true; return foo[];" `failsToCompileWithError` functionCallExpressionNotAFunctionTypeError
    it "Function arguments must match their corresponding parameter type" $
      "let foo = [x: Int, y: Int]: Int -> x + y; foo[3, 'a'];" `failsToCompileWithError` typeExpectationError
    it "The number of arguments in a function call cannot be less than the number of parameters" $
      "let foo = [x: Int, y: Int]: Int -> x + y; foo[1];" `failsToCompileWithError` functionCallExpressionArityError
    it "The number of arguments in a function call cannot be more than the number of parameters" $
      "let foo = [x: Int, y: Int]: Int -> x + y; foo[1, 2, 3];" `failsToCompileWithError` functionCallExpressionArityError

conflictingParameterNamesError :: Error -> Bool
conflictingParameterNamesError (ConflictingParameterNamesError {}) = True
conflictingParameterNamesError _ = False

variableShadowedInDeclarationError :: Error -> Bool
variableShadowedInDeclarationError (VariableShadowedInDeclarationError {}) = True
variableShadowedInDeclarationError _ = False

mutatedParameterError :: Error -> Bool
mutatedParameterError (MutatedParameterError {}) = True
mutatedParameterError _ = False

mutatedCapturedIdentifierError :: Error -> Bool
mutatedCapturedIdentifierError (MutatedCapturedIdentifierError {}) = True
mutatedCapturedIdentifierError _ = False

functionMissingParameterTypeAnnotation :: Error -> Bool
functionMissingParameterTypeAnnotation (FunctionMissingParameterTypeAnnotation {}) = True
functionMissingParameterTypeAnnotation _ = False

functionMissingReturnTypeAnnotation :: Error -> Bool
functionMissingReturnTypeAnnotation (FunctionMissingReturnTypeAnnotation {}) = True
functionMissingReturnTypeAnnotation _ = False

functionBodyTypeError :: Error -> Bool
functionBodyTypeError (FunctionBodyTypeError {}) = True
functionBodyTypeError _ = False

typeExpectationError :: Error -> Bool
typeExpectationError (TypeExpectationError {}) = True
typeExpectationError _ = False

functionCallExpressionNotAFunctionTypeError :: Error -> Bool
functionCallExpressionNotAFunctionTypeError (FunctionCallExpressionNotAFunctionTypeError {}) = True
functionCallExpressionNotAFunctionTypeError _ = False

functionCallExpressionArityError :: Error -> Bool
functionCallExpressionArityError (FunctionCallExpressionArityError {}) = True
functionCallExpressionArityError _ = False