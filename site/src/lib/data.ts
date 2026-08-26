// Content for the Skill Kit landing page.
// Ported from the "SkillKit Landing v5 — The Canon" design.

/**
 * A hand-written pull-quote for one canon work, keyed by its verbatim
 * `sources:` string.
 *
 * OPTIONAL BY DESIGN. The canon itself is derived (`canon.generated.ts`), and
 * `scripts/test-canon-coverage.sh` asserts nothing about this map — so a work
 * with no lesson simply opens to its derived spread, and a missing lesson can
 * never keep a newly declared source off the page. That is what makes 45
 * entries maintainable: curation stays possible without becoming mandatory,
 * and the part that must be complete is the part a script generates.
 */
export type Lessons = Record<string, string>;

export interface Mapping {
	principle: string;
	source: string;
	skill: string;
	what: string;
}

export interface CatalogGroup {
	name: string;
	skills: string[];
}

/**
 * Keys are the verbatim `sources:` string, which is `CanonWork.full`. A key that
 * matches no declared work is dead prose that silently never renders, so the
 * contract suite fails on one.
 */
export const lessons: Lessons = {
	"A Philosophy of Software Design — John Ousterhout":
		"“Design it twice — your first idea is unlikely to be the best.”",
	"Shape Up — Ryan Singer":
		"Set appetite before solution. Name rabbit holes. Declare no-gos.",
	"TDD By Example — Kent Beck":
		"Red, green, refactor — never write code without a failing test.",
	"Refactoring — Martin Fowler":
		"“Make each refactoring step as small as possible, so you can always see the program working.”",
	"Domain-Driven Design — Eric Evans":
		"One ubiquitous language, shared by code, docs, and conversation.",
	"Continuous Delivery — Jez Humble & David Farley":
		"Keep the mainline always releasable; merge in small, verified steps.",
	"Extreme Programming Explained — Kent Beck":
		"Courage through feedback — short loops beat long plans.",
	"Total TypeScript — Matt Pocock":
		"Type-level discipline: inference first, narrowing over assertions.",
};

/**
 * The works an engineer recognizes on sight, in the order the bookcase shows
 * them. Everything not named here keeps the derived order behind them.
 *
 * WHY A HAND-WRITTEN LIST EXISTS AT ALL, given that #273 removed one. The
 * derived order ranks by how many skills are *built on* a work, which is a real
 * signal and the wrong one for the first thing a visiting engineer sees: it put
 * *Thinking in Systems* and *The Design of Everyday Things* on the top board and
 * left *Clean Architecture* 28th, *Continuous Delivery* 19th and *TDD By
 * Example* 14th. The page is a shelf of software engineering practice, and it
 * was leading with the two books on it that are not about software.
 *
 * WHAT MAKES THIS SAFE WHERE #273's LIST WAS NOT. That list was the canon — it
 * decided which works existed, so a work missing from it was a work the reader
 * never saw. This one only permutes: the canon is still every declared source,
 * every one of them still renders, and deleting this array leaves the shelf
 * complete and merely differently sorted. It is the same bargain as `lessons`
 * above — optional curation that cannot subtract — and the contract suite holds
 * both halves: a name here that matches no declared work fails, and the built
 * page is still required to carry all 45 works.
 *
 * Keys are the verbatim `sources:` string, which is `CanonWork.full`.
 */
export const flagships: string[] = [
	"The Pragmatic Programmer — Andrew Hunt & David Thomas",
	"Refactoring — Martin Fowler",
	"Domain-Driven Design — Eric Evans",
	"TDD By Example — Kent Beck",
	"Clean Architecture — Robert C. Martin",
	"A Philosophy of Software Design — John Ousterhout",
	"Continuous Delivery — Jez Humble & David Farley",
	"Growing Object-Oriented Software, Guided by Tests — Freeman & Pryce",
	"Extreme Programming Explained — Kent Beck",
	"Release It! — Michael Nygard",
];

export const mappings: Mapping[] = [
	{ principle: "“Design it twice.”", source: "A Philosophy of Software Design", skill: "/design-an-interface", what: "Generates radically different designs before committing." },
	{ principle: "Appetite before solution", source: "Shape Up", skill: "/write-a-prd", what: "Sets a time budget, names rabbit holes, declares no-gos." },
	{ principle: "Red — green — refactor", source: "TDD By Example", skill: "/tdd", what: "A disciplined loop invoked from every execution." },
	{ principle: "Small, reversible steps", source: "Refactoring", skill: "/request-refactor-plan", what: "Plans refactors as tiny commits that always run." },
	{ principle: "Ubiquitous language", source: "Domain-Driven Design", skill: "/ubiquitous-language", what: "A living glossary with a decisions register." },
	{ principle: "Always releasable", source: "Continuous Delivery", skill: "/pre-merge · /closeout", what: "Architectural review, clean merges, clean teardowns." },
];

export const pipeline: string[] = [
	"/shape",
	"/research",
	"/write-a-prd",
	"/prd-to-issues",
	"/execute",
	"/qa",
	"/pre-merge",
	"/compound",
	"/closeout",
];

export const catalog: CatalogGroup[] = [
	{ name: "Planning", skills: ["shape", "create-milestone", "research", "write-a-prd", "prd-to-issues", "design-an-interface", "api-design-review", "prototype", "mermaid"] },
	{ name: "Development", skills: ["execute", "tdd", "triage-issue", "improve-codebase-architecture", "request-refactor-plan", "ts-audit"] },
	{ name: "Knowledge & QA", skills: ["qa", "pre-merge", "walk-commits", "visual-recap", "compound", "closeout", "ubiquitous-language", "improve-pipeline"] },
	{ name: "Orientation", skills: ["help", "correct-course", "handoff", "re-pitch"] },
	{ name: "Tooling", skills: ["init-pipeline", "setup-pre-commit", "setup-ralph-loop", "git-guardrails-claude-code"] },
];

export const repoUrl = "https://github.com/chrislacey89/skills";
export const installCommand = "npx skills@latest add chrislacey89/skills";
export const fullInstallCommand = "npx skills@latest add chrislacey89/skills --skill '*' --agent claude-code --global -y";
