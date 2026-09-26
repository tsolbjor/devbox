@{
  Severity     = @('Error', 'Warning')
  # Excluded because they contradict this repo's conventions, not by accident:
  ExcludeRules = @(
    'PSAvoidUsingWriteHost',                        # the status lines (done / acting / warning) are the UX
    'PSUseApprovedVerbs',                           # Ensure-* is the idempotency convention
    'PSUseShouldProcessForStateChangingFunctions',  # scripts, not a module: no -WhatIf surface
    'PSUseSingularNouns',                           # Ensure-DevDrivePackageCaches reads better plural
    'PSAvoidUsingInvokeExpression',                 # `fnm env | iex` / starship init are the upstream idiom
    'PSAvoidUsingEmptyCatchBlock',                  # each one is a deliberate, commented best-effort probe
    'PSReviewUnusedParameter'                       # blind to params used inside scriptblock closures ($confirm, AST .Find)
  )
}
