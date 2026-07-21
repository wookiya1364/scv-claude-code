import { SlideDeck } from "@/deck/SlideDeck";
import { getDeck } from "@/deck/decks";

// pnpm dev / build:deck = 주제별 기획서 덱.
// 어느 주제를 볼지는 VITE_DECK_SLUG로 선택(없으면 기본 덱). 주제별로 소스·산출물이 분리된다.
export function App() {
  const deck = getDeck(import.meta.env.VITE_DECK_SLUG);
  return <SlideDeck slides={deck.slides} deckTitle={deck.title} />;
}

export default App;
