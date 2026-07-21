import { SlideDeck } from "@/deck/SlideDeck";
import { getDeck } from "@/deck/decks";
import { MarkdownDeck, loadGeneratedDeck } from "@/deck/MarkdownDeck";

// VITE_DECK_SLUG selects the deck. A generated (data-driven) deck.json wins;
// otherwise fall back to a hand-authored deck (the sample). Missing → sample.
export function App() {
  const slug = import.meta.env.VITE_DECK_SLUG;
  const generated = loadGeneratedDeck(slug);
  if (generated) return <MarkdownDeck data={generated} />;

  const deck = getDeck(slug);
  return <SlideDeck slides={deck.slides} deckTitle={deck.title} />;
}

export default App;
