param(
    [string]$InputDll = "$PSScriptRoot\..\vendor\CheatCleanup\CheatCleanup.dll",
    [string]$OutputDll = "$PSScriptRoot\..\artifacts\server-repair\CheatCleanup\CheatCleanup.dll",
    [string]$CecilDll = "$PSScriptRoot\..\vendor\BepInEx\Mono.Cecil.dll",
    [string]$ValheimDll = "$PSScriptRoot\..\vendor\assembly_valheim.dll"
)

$ErrorActionPreference = 'Stop'
[void][System.Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $CecilDll))

$reader = [Mono.Cecil.ReaderParameters]::new()
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Resolve-Path -LiteralPath $InputDll), $reader)
$valheimAssembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Resolve-Path -LiteralPath $ValheimDll), $reader)
$valheimZnetType = $valheimAssembly.MainModule.Types | Where-Object FullName -eq 'ZNet'
$valheimZnetGetInstance = $valheimZnetType.Methods | Where-Object { $_.Name -eq 'get_instance' -and $_.Parameters.Count -eq 0 } | Select-Object -First 1
$valheimGetWorld = $valheimZnetType.Methods | Where-Object { $_.Name -eq 'GetWorld' -and $_.Parameters.Count -eq 0 } | Select-Object -First 1
$valheimSaveWorld = $valheimZnetType.Methods | Where-Object { $_.Name -eq 'SaveWorld' -and $_.Parameters.Count -eq 1 } | Select-Object -First 1
$valheimZdoType = $valheimAssembly.MainModule.Types | Where-Object FullName -eq 'ZDOMan'
$valheimZdoObjectType = $valheimAssembly.MainModule.Types | Where-Object FullName -eq 'ZDO'
$valheimZnetSceneType = $valheimAssembly.MainModule.Types | Where-Object FullName -eq 'ZNetScene'
$valheimZdoGetInstance = $valheimZdoType.Methods | Where-Object { $_.Name -eq 'get_instance' -and $_.Parameters.Count -eq 0 } | Select-Object -First 1
$valheimZdoNrObjects = $valheimZdoType.Methods | Where-Object { $_.Name -eq 'NrOfObjects' -and $_.Parameters.Count -eq 0 } | Select-Object -First 1
$valheimZdoSetDirtySector = $valheimZdoType.Methods | Where-Object { $_.Name -eq 'SetDirtySector' -and $_.Parameters.Count -eq 1 } | Select-Object -First 1
$valheimZdoSetDirtyPortals = $valheimZdoType.Methods | Where-Object { $_.Name -eq 'SetDirtyPortals' -and $_.Parameters.Count -eq 0 } | Select-Object -First 1
$valheimZdoToString = $valheimZdoObjectType.Methods | Where-Object { $_.Name -eq 'ToString' -and $_.Parameters.Count -eq 0 } | Select-Object -First 1
$valheimZdoGetPrefab = $valheimZdoObjectType.Methods | Where-Object { $_.Name -eq 'GetPrefab' -and $_.Parameters.Count -eq 0 } | Select-Object -First 1
$valheimZnetSceneGetInstance = $valheimZnetSceneType.Methods | Where-Object { $_.Name -eq 'get_instance' -and $_.Parameters.Count -eq 0 } | Select-Object -First 1
$valheimZnetSceneGetPrefab = $valheimZnetSceneType.Methods | Where-Object { $_.Name -eq 'GetPrefab' -and $_.Parameters.Count -eq 1 -and $_.Parameters[0].ParameterType.FullName -eq 'System.Int32' } | Select-Object -First 1
if (-not $valheimZnetType -or -not $valheimZnetGetInstance -or -not $valheimGetWorld -or -not $valheimSaveWorld -or -not $valheimZdoType -or -not $valheimZdoObjectType -or -not $valheimZnetSceneType -or -not $valheimZdoGetInstance -or -not $valheimZdoNrObjects -or -not $valheimZdoSetDirtySector -or -not $valheimZdoSetDirtyPortals -or -not $valheimZdoToString -or -not $valheimZdoGetPrefab -or -not $valheimZnetSceneGetInstance -or -not $valheimZnetSceneGetPrefab) { throw 'Métodos atuais do Valheim não encontrados na DLL oficial.' }
$module = $assembly.MainModule
$plugin = $module.Types | Where-Object FullName -eq 'CheatCleanup.CheatCleanupPlugin'
$service = $module.Types | Where-Object FullName -eq 'CheatCleanup.CleanupService'
$report = $module.Types | Where-Object FullName -eq 'CheatCleanup.CleanupReport'
$access = $module.Types | Where-Object FullName -eq 'CheatCleanup.ValheimAccess'
if (-not $plugin -or -not $service -or -not $report -or -not $access) { throw 'Tipos esperados não encontrados.' }

$run = $service.Methods | Where-Object { $_.Name -eq 'Run' -and $_.Parameters.Count -eq 1 } | Select-Object -First 1
$scanWorld = $service.Methods | Where-Object { $_.Name -eq 'ScanWorldZdos' } | Select-Object -First 1
$syncLoaded = $service.Methods | Where-Object { $_.Name -eq 'SynchronizeLoadedRuntimeObjects' } | Select-Object -First 1
$requestSave = $access.Methods | Where-Object { $_.Name -eq 'RequestNativeSave' } | Select-Object -First 1
$removeZdoBool = $access.Methods | Where-Object { $_.Name -eq 'RemoveZdoBool' -and $_.Parameters.Count -eq 2 } | Select-Object -First 1
$setZdoBytes = $access.Methods | Where-Object { $_.Name -eq 'SetZdoBytes' -and $_.Parameters.Count -eq 3 } | Select-Object -First 1
$tryInvokeNoArg = $service.Methods | Where-Object { $_.Name -eq 'TryInvokeNoArg' -and $_.Parameters.Count -eq 2 } | Select-Object -First 1
$znet = $access.Methods | Where-Object { $_.Name -eq 'get_ZNetInstance' } | Select-Object -First 1
$zdoMan = $access.Methods | Where-Object { $_.Name -eq 'get_ZdoManInstance' } | Select-Object -First 1
$world = $access.Methods | Where-Object { $_.Name -eq 'GetWorld' } | Select-Object -First 1
$allZdos = $access.Methods | Where-Object { $_.Name -eq 'GetAllZdos' } | Select-Object -First 1
$toConsole = $report.Methods | Where-Object { $_.Name -eq 'ToConsoleText' } | Select-Object -First 1
$reportCtor = $report.Methods | Where-Object { $_.IsConstructor -and $_.Parameters.Count -eq 0 } | Select-Object -First 1
$warningsField = $report.Fields | Where-Object { $_.Name -eq 'Warnings' } | Select-Object -First 1
if (-not $run -or -not $scanWorld -or -not $syncLoaded -or -not $requestSave -or -not $removeZdoBool -or -not $setZdoBytes -or -not $tryInvokeNoArg -or -not $znet -or -not $zdoMan -or -not $world -or -not $allZdos -or -not $toConsole -or -not $reportCtor) {
    throw 'Métodos esperados não encontrados.'
}
$tryInvokeNoArg.IsPrivate = $false
$tryInvokeNoArg.IsPublic = $true

# SaveWorldAndPlayerProfiles() routes through RPC_Save(null) on a dedicated
# server, which reaches HardSaveBlock with a null RPC. Invoke SaveWorld(bool)
# directly instead so the cleaned ZDOs are persisted without a client RPC.
$znetTypeField = ($world.Body.Instructions | Where-Object { $_.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldsfld -and $_.Operand.Name -eq 'ZNetType' } | Select-Object -First 1).Operand
$methodHelperCall = ($requestSave.Body.Instructions | Where-Object { $_.Operand -and $_.Operand.Name -eq 'Method' } | Select-Object -First 1).Operand
$methodNullableBoolCtor = ($requestSave.Body.Instructions | Where-Object { $_.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Newobj } | Select-Object -First 1).Operand
$invokeCall = ($world.Body.Instructions | Where-Object { $_.Operand -and $_.Operand.Name -eq 'Invoke' } | Select-Object -First 1).Operand
if (-not $znetTypeField -or -not $methodHelperCall -or -not $methodNullableBoolCtor -or -not $invokeCall) { throw 'Helpers para o salvamento direto não encontrados.' }

# ZDO.RemoveBool/SetByteArray update the payload but do not advance the ZDO
# data revision in this Valheim build. Without that revision bump, SaveWorld
# sees no dirty chunks and the change disappears after a reload.
$removeBoolField = ($removeZdoBool.Body.Instructions | Where-Object { $_.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldsfld } | Select-Object -First 1).Operand
$removeInvokeCall = ($removeZdoBool.Body.Instructions | Where-Object { $_.Operand -and $_.Operand.Name -eq 'Invoke' } | Select-Object -First 1).Operand
if (-not $removeBoolField -or -not $removeInvokeCall) { throw 'Helpers para marcar ZDOs alterados não encontrados.' }

function Add-RevisionBump($method, $field, $invokeCall, $tryInvokeNoArg, $extraArgumentCount, $zdoManMethod, $zdoManType, $zdoObjectType, $setDirtySector, $setDirtyPortals) {
    $body = $method.Body
    $body.Instructions.Clear()
    $body.ExceptionHandlers.Clear()
    $body.Variables.Clear()
    $body.InitLocals = $false
    $body.MaxStackSize = 5
    $il = $body.GetILProcessor()
    $done = $il.Create([Mono.Cecil.Cil.OpCodes]::Ret)
    $hasMethod = $il.Create([Mono.Cecil.Cil.OpCodes]::Nop)
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Brfalse, $done))
    if ($extraArgumentCount -eq 1) {
        $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_1))
        $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Brfalse, $done))
    }
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldsfld, $module.ImportReference($field)))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Dup))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $hasMethod))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Pop))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Br, $done))
    $il.Append($hasMethod)
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4, $extraArgumentCount))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Newarr, $module.TypeSystem.Object))
    if ($extraArgumentCount -eq 1) {
        $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Dup))
        $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
        $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_1))
        $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Box, $module.TypeSystem.Int32))
        $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Stelem_Ref))
    }
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($invokeCall)))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Pop))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, 'IncreaseDataRevision'))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($tryInvokeNoArg)))
    $hasDirty = $il.Create([Mono.Cecil.Cil.OpCodes]::Nop)
    $skipDirty = $il.Create([Mono.Cecil.Cil.OpCodes]::Nop)
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($zdoManMethod)))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Dup))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $hasDirty))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Pop))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Br, $skipDirty))
    $il.Append($hasDirty)
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Castclass, $module.ImportReference($zdoManType)))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Dup))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Castclass, $module.ImportReference($zdoObjectType)))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($setDirtySector)))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($setDirtyPortals)))
    $il.Append($skipDirty)
    $il.Append($done)
}

$removeBody = $removeZdoBool.Body
$removeBodyInvoke = $removeInvokeCall
Add-RevisionBump $removeZdoBool $removeBoolField $removeBodyInvoke $tryInvokeNoArg 1 $zdoMan $valheimZdoType $valheimZdoObjectType $valheimZdoSetDirtySector $valheimZdoSetDirtyPortals

$setBytesField = ($setZdoBytes.Body.Instructions | Where-Object { $_.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldsfld } | Select-Object -First 1).Operand
$setBytesInvokeCall = ($setZdoBytes.Body.Instructions | Where-Object { $_.Operand -and $_.Operand.Name -eq 'Invoke' } | Select-Object -First 1).Operand
if (-not $setBytesField -or -not $setBytesInvokeCall) { throw 'Helpers para marcar bytes ZDO alterados não encontrados.' }

function Add-ByteRevisionBump($method, $field, $invokeCall, $tryInvokeNoArg, $zdoManMethod, $zdoManType, $zdoObjectType, $setDirtySector, $setDirtyPortals) {
    $body = $method.Body
    $body.Instructions.Clear()
    $body.ExceptionHandlers.Clear()
    $body.Variables.Clear()
    $body.InitLocals = $false
    $body.MaxStackSize = 6
    $il = $body.GetILProcessor()
    $done = $il.Create([Mono.Cecil.Cil.OpCodes]::Ret)
    $hasMethod = $il.Create([Mono.Cecil.Cil.OpCodes]::Nop)
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Brfalse, $done))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_1))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Brfalse, $done))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_2))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Brfalse, $done))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldsfld, $module.ImportReference($field)))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Dup))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $hasMethod))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Pop))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Br, $done))
    $il.Append($hasMethod)
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_2))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Newarr, $module.TypeSystem.Object))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Dup))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_1))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Box, $module.TypeSystem.Int32))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Stelem_Ref))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Dup))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_2))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Stelem_Ref))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($invokeCall)))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Pop))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, 'IncreaseDataRevision'))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($tryInvokeNoArg)))
    $hasDirty = $il.Create([Mono.Cecil.Cil.OpCodes]::Nop)
    $skipDirty = $il.Create([Mono.Cecil.Cil.OpCodes]::Nop)
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($zdoManMethod)))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Dup))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $hasDirty))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Pop))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Br, $skipDirty))
    $il.Append($hasDirty)
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Castclass, $module.ImportReference($zdoManType)))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Dup))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Castclass, $module.ImportReference($zdoObjectType)))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($setDirtySector)))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($setDirtyPortals)))
    $il.Append($skipDirty)
    $il.Append($done)
}

Add-ByteRevisionBump $setZdoBytes $setBytesField $setBytesInvokeCall $tryInvokeNoArg $zdoMan $valheimZdoType $valheimZdoObjectType $valheimZdoSetDirtySector $valheimZdoSetDirtyPortals

# Keep a compact diagnostic for the few world ZDOs that carry the marker. The
# official ZDO.ToString() includes its identity and prefab, which lets us see
# whether a marker is regenerated by a runtime object after a reload.
$scanWarningsAdd = ($scanWorld.Body.Instructions | Where-Object { $_.Operand -and $_.Operand.Name -eq 'Add' } | Select-Object -First 1).Operand
$cheatedFlagLoad = ($scanWorld.Body.Instructions | Where-Object { $_.Operand -and $_.Operand.Name -eq 'ZdoCheatedFlags' } | Select-Object -First 1)
$zdoLocal = ($scanWorld.Body.Instructions | Where-Object { $_.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldloc_S -and $_.Operand -and $_.Operand.Index -eq 7 } | Select-Object -First 1).Operand
$objectToStringCall = ($module.Types | ForEach-Object { $_.Methods } | ForEach-Object { $_.Body.Instructions } | Where-Object { $_.Operand -and $_.Operand.FullName -eq 'System.String System.Object::ToString()' } | Select-Object -First 1).Operand
$stringConcat2Call = ($service.Methods | ForEach-Object { $_.Body.Instructions } | Where-Object { $_.Operand -and $_.Operand.FullName -eq 'System.String System.String::Concat(System.String,System.String)' } | Select-Object -First 1).Operand
if (-not $warningsField -or -not $scanWarningsAdd -or -not $cheatedFlagLoad -or -not $cheatedFlagLoad.Previous -or -not $cheatedFlagLoad.Previous.Previous -or -not $zdoLocal -or -not $objectToStringCall -or -not $stringConcat2Call) { throw 'Helpers para diagnóstico dos ZDOs não encontrados.' }
$logCheatedZdoAttributes = [Mono.Cecil.MethodAttributes](([int][Mono.Cecil.MethodAttributes]::Private) -bor ([int][Mono.Cecil.MethodAttributes]::Static))
$logCheatedZdo = [Mono.Cecil.MethodDefinition]::new('LogCheatedZdo', $logCheatedZdoAttributes, $module.TypeSystem.Void)
[void]$logCheatedZdo.Parameters.Add([Mono.Cecil.ParameterDefinition]::new('report', [Mono.Cecil.ParameterAttributes]::None, $module.ImportReference($report)))
[void]$logCheatedZdo.Parameters.Add([Mono.Cecil.ParameterDefinition]::new('zdo', [Mono.Cecil.ParameterAttributes]::None, $module.TypeSystem.Object))
[void]$service.Methods.Add($logCheatedZdo)
$logBody = $logCheatedZdo.Body
$logBody.MaxStackSize = 4
$logIl = $logBody.GetILProcessor()
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $module.ImportReference($warningsField)))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_1))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($valheimZdoToString)))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($scanWarningsAdd)))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $module.ImportReference($warningsField)))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, 'prefab='))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_1))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($valheimZdoGetPrefab)))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Box, $module.TypeSystem.Int32))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($objectToStringCall)))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($stringConcat2Call)))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($scanWarningsAdd)))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $module.ImportReference($warningsField)))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, 'name='))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($valheimZnetSceneGetInstance)))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_1))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($valheimZdoGetPrefab)))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($valheimZnetSceneGetPrefab)))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($objectToStringCall)))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($stringConcat2Call)))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($scanWarningsAdd)))
$logIl.Append($logIl.Create([Mono.Cecil.Cil.OpCodes]::Ret))
$scanBody = $scanWorld.Body
$scanIl = $scanBody.GetILProcessor()
$scanInsertBefore = $cheatedFlagLoad.Previous.Previous
$scanIl.InsertBefore($scanInsertBefore, $scanIl.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$scanIl.InsertBefore($scanInsertBefore, $scanIl.Create([Mono.Cecil.Cil.OpCodes]::Ldloc, $zdoLocal))
$scanIl.InsertBefore($scanInsertBefore, $scanIl.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($logCheatedZdo)))

$saveBody = $requestSave.Body
$saveBody.Instructions.Clear()
$saveBody.ExceptionHandlers.Clear()
$saveBody.Variables.Clear()
$saveBody.InitLocals = $true
$saveBody.MaxStackSize = 6
$saveZnetVar = [Mono.Cecil.Cil.VariableDefinition]::new($module.TypeSystem.Object)
[void]$saveBody.Variables.Add($saveZnetVar)
$saveIl = $saveBody.GetILProcessor()
$saveFalse = $saveIl.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0)
$saveHaveMethod = $saveIl.Create([Mono.Cecil.Cil.OpCodes]::Nop)
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($znet)))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Stloc, $saveZnetVar))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Ldloc, $saveZnetVar))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Brfalse, $saveFalse))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Ldsfld, $module.ImportReference($znetTypeField)))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, 'SaveWorld'))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Newobj, $module.ImportReference($methodNullableBoolCtor)))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($methodHelperCall)))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Dup))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $saveHaveMethod))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Pop))
$saveIl.Append($saveFalse)
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Ret))
$saveIl.Append($saveHaveMethod)
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Ldloc, $saveZnetVar))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Newarr, $module.TypeSystem.Object))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Dup))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Box, $module.TypeSystem.Boolean))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Stelem_Ref))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($invokeCall)))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Pop))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
$saveIl.Append($saveIl.Create([Mono.Cecil.Cil.OpCodes]::Ret))

# A versão atual mantém o ZDOMan do mundo em ZNet.m_zdoMan; o singleton
# ZDOMan.s_instance não é a instância usada pelo servidor dedicado.
$zdoFieldCall = ($allZdos.Body.Instructions | Where-Object { $_.Operand -and $_.Operand.Name -eq 'GetField' } | Select-Object -First 1).Operand
$findLoadedObjects = $access.Methods | Where-Object { $_.Name -eq 'FindLoadedObjects' -and $_.Parameters.Count -eq 1 } | Select-Object -First 1
$enumerateCall = ($allZdos.Body.Instructions | Where-Object { $_.Operand -and $_.Operand.Name -eq 'Enumerate' } | Select-Object -First 1).Operand
$getEnumeratorCall = ($allZdos.Body.Instructions | Where-Object { $_.Operand -and $_.Operand.Name -eq 'GetEnumerator' } | Select-Object -First 1).Operand
$moveNextCall = ($allZdos.Body.Instructions | Where-Object { $_.Operand -and $_.Operand.Name -eq 'MoveNext' } | Select-Object -First 1).Operand
$currentCall = ($allZdos.Body.Instructions | Where-Object { $_.Operand -and $_.Operand.Name -eq 'get_Current' } | Select-Object -First 1).Operand
if (-not $zdoFieldCall -or -not $findLoadedObjects -or -not $enumerateCall -or -not $getEnumeratorCall -or -not $moveNextCall -or -not $currentCall) { throw 'Acesso ao ZNet carregado não encontrado.' }
$zbody = $zdoMan.Body
$zbody.Instructions.Clear()
$zbody.ExceptionHandlers.Clear()
$zbody.Variables.Clear()
$zbody.InitLocals = $true
$zbody.MaxStackSize = 2
$zEnumerator = [Mono.Cecil.Cil.VariableDefinition]::new($module.ImportReference($moveNextCall.DeclaringType))
[void]$zbody.Variables.Add($zEnumerator)
$zil = $zbody.GetILProcessor()
$zfindObjects = $zil.Create([Mono.Cecil.Cil.OpCodes]::Nop)
$zhasStaticNet = $zil.Create([Mono.Cecil.Cil.OpCodes]::Nop)
$zloopObjects = $zil.Create([Mono.Cecil.Cil.OpCodes]::Nop)
$zreturn = $zil.Create([Mono.Cecil.Cil.OpCodes]::Ret)
$znoObjects = $zil.Create([Mono.Cecil.Cil.OpCodes]::Ldnull)
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($znet)))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Dup))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $zhasStaticNet))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Pop))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Br, $zfindObjects))
$zil.Append($zhasStaticNet)
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, 'm_zdoMan'))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($zdoFieldCall)))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Dup))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $zreturn))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Pop))
$zil.Append($zfindObjects)
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, 'ZNet'))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($findLoadedObjects)))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($enumerateCall)))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($getEnumeratorCall)))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Stloc, $zEnumerator))
$zil.Append($zloopObjects)
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Ldloc, $zEnumerator))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($moveNextCall)))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Brfalse, $znoObjects))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Ldloc, $zEnumerator))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($currentCall)))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, 'm_zdoMan'))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($zdoFieldCall)))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Dup))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $zreturn))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Pop))
$zil.Append($zil.Create([Mono.Cecil.Cil.OpCodes]::Br, $zloopObjects))
$zil.Append($znoObjects)
$zil.Append($zreturn)

$body = $run.Body
$body.Instructions.Clear()
$body.ExceptionHandlers.Clear()
$body.Variables.Clear()
$body.InitLocals = $true
$body.MaxStackSize = 3
$reportVar = [Mono.Cecil.Cil.VariableDefinition]::new($module.ImportReference($report))
[void]$body.Variables.Add($reportVar)
$il = $body.GetILProcessor()
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Newobj, $module.ImportReference($reportCtor)))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Stloc, $reportVar))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldloc, $reportVar))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($scanWorld)))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldloc, $reportVar))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($syncLoaded)))
$afterSave = $il.Create([Mono.Cecil.Cil.OpCodes]::Nop)
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Brfalse_S, $afterSave))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($requestSave)))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Pop))
$il.Append($afterSave)
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldloc, $reportVar))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ret))

$autoField = $plugin.Fields | Where-Object Name -eq '__autoWorldCleaned' | Select-Object -First 1
if (-not $autoField) {
    $autoField = [Mono.Cecil.FieldDefinition]::new('__autoWorldCleaned', [Mono.Cecil.FieldAttributes]::Private, $module.TypeSystem.Boolean)
    [void]$plugin.Fields.Add($autoField)
}
$tickField = $plugin.Fields | Where-Object Name -eq '__autoWorldTicks' | Select-Object -First 1
if (-not $tickField) {
    $tickField = [Mono.Cecil.FieldDefinition]::new('__autoWorldTicks', [Mono.Cecil.FieldAttributes]::Private, $module.TypeSystem.Int32)
    [void]$plugin.Fields.Add($tickField)
}
$diagField = $plugin.Fields | Where-Object Name -eq '__autoWorldDiag' | Select-Object -First 1
if (-not $diagField) {
    $diagField = [Mono.Cecil.FieldDefinition]::new('__autoWorldDiag', [Mono.Cecil.FieldAttributes]::Private, $module.TypeSystem.Boolean)
    [void]$plugin.Fields.Add($diagField)
}

$update = $plugin.Methods | Where-Object { $_.Name -eq 'Update' -and $_.Parameters.Count -eq 0 } | Select-Object -First 1
if ($update) { [void]$plugin.Methods.Remove($update) }
$updateAttrs = [Mono.Cecil.MethodAttributes]([int][Mono.Cecil.MethodAttributes]::Private -bor [int][Mono.Cecil.MethodAttributes]::HideBySig)
$update = [Mono.Cecil.MethodDefinition]::new('Update', $updateAttrs, $module.TypeSystem.Void)
[void]$plugin.Methods.Add($update)
$update.Body.InitLocals = $true
$update.Body.MaxStackSize = 4
$reportLocal = [Mono.Cecil.Cil.VariableDefinition]::new($module.ImportReference($report))
[void]$update.Body.Variables.Add($reportLocal)
$uil = $update.Body.GetILProcessor()
$diagLoggerGetter = ($plugin.Methods | ForEach-Object { $_.Body.Instructions } | Where-Object { $_.Operand -and $_.Operand.Name -eq 'get_Logger' } | Select-Object -First 1).Operand
$diagLogInfo = ($plugin.Methods | ForEach-Object { $_.Body.Instructions } | Where-Object { $_.Operand -and $_.Operand.Name -eq 'LogInfo' } | Select-Object -First 1).Operand
if (-not $diagLoggerGetter -or -not $diagLogInfo) { throw 'Logger do plugin não encontrado.' }
$done = $uil.Create([Mono.Cecil.Cil.OpCodes]::Ret)
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $autoField))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $done))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Dup))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $tickField))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Add))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Stfld, $tickField))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $tickField))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4, 30000))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Blt, $done))
$diagDone = $uil.Create([Mono.Cecil.Cil.OpCodes]::Nop)
$diagNull = $uil.Create([Mono.Cecil.Cil.OpCodes]::Nop)
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $diagField))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $diagDone))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Stfld, $diagField))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($diagLoggerGetter)))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($zdoMan)))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Brfalse, $diagNull))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, 'AUTO-DIAG ZDOMan=NONNULL'))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($diagLogInfo)))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Br, $diagDone))
$uil.Append($diagNull)
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, 'AUTO-DIAG ZDOMan=NULL'))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($diagLogInfo)))
$uil.Append($diagDone)
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldnull))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($valheimGetWorld)))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Brfalse, $done))
$hasZdoMan = $uil.Create([Mono.Cecil.Cil.OpCodes]::Nop)
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($zdoMan)))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Dup))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $hasZdoMan))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Pop))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Br, $done))
$uil.Append($hasZdoMan)
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($valheimZdoNrObjects)))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ble, $done))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Stfld, $autoField))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($run)))
$uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Stloc, $reportLocal))
$loggerGetter = ($plugin.Methods | ForEach-Object { $_.Body.Instructions } | Where-Object { $_.Operand -and $_.Operand.Name -eq 'get_Logger' } | Select-Object -First 1).Operand
$logInfo = ($plugin.Methods | ForEach-Object { $_.Body.Instructions } | Where-Object { $_.Operand -and $_.Operand.Name -eq 'LogInfo' } | Select-Object -First 1).Operand
if ($loggerGetter -and $logInfo) {
    $uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
    $uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($loggerGetter)))
    $uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldloc, $reportLocal))
    $uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, 'AUTO-WORLD'))
    $uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($toConsole)))
    $uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($logInfo)))

    # Segunda passagem somente-leitura: confirma que não restaram marcações.
    $uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
    $uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($run)))
    $uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Stloc, $reportLocal))
    $uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
    $uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($loggerGetter)))
    $uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldloc, $reportLocal))
    $uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, 'AUTO-WORLD-VERIFY'))
    $uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($toConsole)))
    $uil.Append($uil.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($logInfo)))
}
$uil.Append($done)

$writer = [Mono.Cecil.WriterParameters]::new()
$assembly.Write($OutputDll, $writer)
Write-Output "Criado: $OutputDll"
