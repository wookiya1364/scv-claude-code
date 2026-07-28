import path from "path"
import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"
import { viteSingleFile } from "vite-plugin-singlefile"

// 자기완결 단일 HTML 빌드 — Cycle 0 기획서 덱을 PR 아티팩트로 배포한다.
// 결과물(dist-deck/index.html)은 JS·CSS·폰트가 전부 인라인되어, 다운로드해서 열면 오프라인·인터랙티브로 동작한다.
export default defineConfig({
  plugins: [react(), tailwindcss(), viteSingleFile()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  // 사이드 패널이 레포 루트 docs/*(기획서 원문)를 ?raw로 불러오므로 상위 디렉터리 허용.
  server: {
    fs: { allow: [path.resolve(__dirname, "..")] },
  },
  build: {
    outDir: "dist-deck",
    assetsInlineLimit: 100_000_000, // 폰트 등 모든 에셋을 base64로 인라인(외부 파일 0)
    cssCodeSplit: false,
    chunkSizeWarningLimit: 100_000,
  },
})
