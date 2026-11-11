# Profiles — MLX setup (one-time)

Hush provides on-device LLM post-processing through **MLX Swift**, including Qwen 2.5 1.5B, Qwen 3 1.7B, and the quality-focused Qwen 3.5 2B 4-bit model. The Swift code compiles without the MLX packages and gracefully degrades to "raw transcript + HUD notice" when MLX isn't present, so the build is always green.

## Step 1 — Add `mlx-swift-lm`

1. Open `Hush/Hush.xcodeproj`.
2. **File → Add Package Dependencies…**
3. Paste: `https://github.com/ml-explore/mlx-swift-lm`
4. Dependency Rule: **Up to Next Minor Version** from `3.31.3` (or the latest tag at the time of install).
5. Click **Add Package**.
6. ⚠️ **CRITICAL** — in the product-selection sheet that appears, check the **Add to Target → Hush** column for these three products:
   - ✅ `MLXLLM`
   - ✅ `MLXLMCommon`
   - ✅ `MLXHuggingFace`

   If you click **Add Package** without checking the target for each product, the package will appear in the navigator but the symbols won't actually be linked into the app — `canImport(MLXLLM)` will be false at compile time and `LLMRuntime.downloadQwen()` will throw "MLX-Swift isn't installed". To fix after-the-fact: Project → Hush target → General → **Frameworks, Libraries, and Embedded Content** → **+** → search and add each of the three.

## Step 2 — Add `swift-huggingface`

1. **File → Add Package Dependencies…** again.
2. Paste: `https://github.com/huggingface/swift-huggingface`
3. Dependency Rule: **Up to Next Major Version** from `1.0.0`.
4. Click **Add Package**.
5. Check:
   - ✅ `HuggingFace`

That's it.

## Step 3 — Build & try

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Hush/Hush.xcodeproj \
             -scheme Hush -configuration Debug build
```

Each model is an explicit one-time download from Hugging Face using the standard MLX downloader. Hush combines the upstream snapshot total with the standard `URLSessionTask` byte counts to display a real percentage and smoothed time estimate without replacing the library's download, cache, or resume behavior. After the transfer reaches 100%, the state changes to local preparation until MLX finishes loading the model. The model is cached on this Mac and subsequent runs load it locally.

## What the packages provide

- **`MLXLLM`** — the language-model implementations (Qwen, Llama, Phi, Gemma…) compiled to MLX kernels.
- **`MLXLMCommon`** — `ModelContainer`, `ChatSession`, `GenerateParameters`, `Memory.cacheLimit` (the public surface `LLMRuntime` actually calls).
- **`MLXHuggingFace`** - Swift macros `#hubDownloader()` and `#huggingFaceTokenizerLoader()` that produce a `Downloader`/`TokenizerLoader` backed by a HuggingFace `HubClient`.
- **`HuggingFace`** — the underlying `HubClient` (download + cache management at `~/Documents/huggingface/...`, sibling to the existing WhisperKit cache).

## Why not bundle these in the repo as already-resolved SPM?

The advisor flagged hand-editing `project.pbxproj` to add SPM packages as a real footgun: SPM entries span four pbxproj sections (`XCRemoteSwiftPackageReference`, `XCSwiftPackageProductDependency` ×2, `PBXBuildFile`, `PBXFrameworksBuildPhase`) and one bad UUID corrupts the project. 30 seconds in the Xcode UI beats an hour debugging.

## Removing the dependency

If you ever want to disable the LLM path:
1. Project → Hush target → **Package Dependencies** → select the package → click **−**.
2. The `canImport(...)` guards in `LLMRuntime.swift` and `LLMPostProcessor.swift` deactivate; non-Raw profiles automatically fall back to "AI not installed, pasted raw" with no further changes.
