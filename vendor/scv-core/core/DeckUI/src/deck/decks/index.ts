import { type Slide } from "@/deck/SlideDeck";
import { sampleDeck } from "./sample/slides";

// A deck = a title + ordered slides. /scv:deck generates one folder per deck
// under decks/<slug>/ and registers it here.
export interface Deck {
  title: string;
  slides: Slide[];
}

const DECKS: Record<string, Deck> = {
  sample: sampleDeck,
};

const DEFAULT_SLUG = "sample";

// Selected at build time via VITE_DECK_SLUG (see App.tsx). Falls back to the
// default deck when the slug is missing or unknown.
export function getDeck(slug?: string): Deck {
  return DECKS[slug ?? DEFAULT_SLUG] ?? DECKS[DEFAULT_SLUG];
}
