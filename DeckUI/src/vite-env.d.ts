/// <reference types="vite/client" />

interface ImportMetaEnv {
  // 어느 주제 덱을 빌드/표시할지. build:deck 시 주입, 없으면 기본 덱.
  readonly VITE_DECK_SLUG?: string;
}
interface ImportMeta {
  readonly env: ImportMetaEnv;
}
