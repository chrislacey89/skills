// Content for the Skill Kit landing page.
// Ported from the "SkillKit Landing v5 — The Canon" design.

export interface Book {
	/** Short spine title. */
	title: string;
	/** Author surname used on the spine and as the detail key. */
	author: string;
	/** Full "Title — Author" shown on hover. */
	full: string;
	/** Spine height. */
	h: string;
	/** Spine color. */
	color: string;
	/** Ink color for the vertical spine label. */
	ink: string;
}

export interface BookDetail {
	/** The pull-quote lesson on the left page. */
	lesson: string;
	/** SKILL.md this book feeds into. */
	file: string;
	/** Frontmatter excerpt shown as a code block. */
	fm: string;
	/** Prose excerpt from the skill. */
	excerpt: string;
}

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

export const shelf: Book[] = [
	{ title: "A Philosophy of Software Design", author: "Ousterhout", full: "A Philosophy of Software Design — John Ousterhout", h: "352px", color: "#7A3B2E", ink: "#F0E9D8" },
	{ title: "Shape Up", author: "Singer", full: "Shape Up — Ryan Singer", h: "260px", color: "#31536B", ink: "#F0E9D8" },
	{ title: "TDD By Example", author: "Beck", full: "TDD By Example — Kent Beck", h: "282px", color: "#6B5B2E", ink: "#F0E9D8" },
	{ title: "Refactoring", author: "Fowler", full: "Refactoring — Martin Fowler", h: "310px", color: "#3E5C46", ink: "#F0E9D8" },
	{ title: "Domain-Driven Design", author: "Evans", full: "Domain-Driven Design — Eric Evans", h: "322px", color: "#54364F", ink: "#F0E9D8" },
	{ title: "Continuous Delivery", author: "Humble & Farley", full: "Continuous Delivery — Jez Humble & David Farley", h: "292px", color: "#2E4A52", ink: "#F0E9D8" },
	{ title: "XP Explained", author: "Beck", full: "Extreme Programming Explained — Kent Beck", h: "252px", color: "#8A6A32", ink: "#1C2822" },
	{ title: "Total TypeScript", author: "Pocock", full: "Total TypeScript — Matt Pocock", h: "272px", color: "#2F4238", ink: "#F0E9D8" },
];

// Keyed by `${author}-${title}` to match the shelf entries above.
export const bookDetails: Record<string, BookDetail> = {
	"Ousterhout-A Philosophy of Software Design": {
		lesson: "“Design it twice — your first idea is unlikely to be the best.”",
		file: "design-an-interface/SKILL.md",
		fm: 'sources:\n  primary:\n    - "A Philosophy of Software Design — John Ousterhout"\n  secondary:\n    - "Designing Web APIs — Jin, Sahni, Shevat"',
		excerpt: "Based on “Design It Twice”: your first idea is unlikely to be the best. Generate multiple radically different designs, then compare — method count, surface area, depth, caller ergonomics, evolvability.",
	},
	"Singer-Shape Up": {
		lesson: "Set appetite before solution. Name rabbit holes. Declare no-gos.",
		file: "write-a-prd/SKILL.md",
		fm: 'sources:\n  primary:\n    - "Shape Up — Ryan Singer"\n  secondary:\n    - "A Philosophy of Software Design — John Ousterhout"\n    - "Software Estimation — Steve McConnell"\n    - "Thinking in Bets — Annie Duke"',
		excerpt: "This skill produces a shaped pitch — a PRD that’s rough enough for builder judgment, solved enough to ship, and bounded by an explicit time appetite.",
	},
	"Beck-TDD By Example": {
		lesson: "Red, green, refactor — never write code without a failing test.",
		file: "tdd/SKILL.md",
		fm: 'sources:\n  primary:\n    - "TDD By Example — Kent Beck"\n  secondary:\n    - "Unit Testing — Vladimir Khorikov"\n    - "Refactoring — Martin Fowler"\n    - "Growing Object-Oriented Software — Freeman & Pryce"',
		excerpt: "Tests should verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn’t. Test difficulty is a design signal, not an obstacle to work around.",
	},
	"Fowler-Refactoring": {
		lesson: "“Make each refactoring step as small as possible, so you can always see the program working.”",
		file: "request-refactor-plan/SKILL.md",
		fm: 'sources:\n  primary:\n    - "Refactoring — Martin Fowler"',
		excerpt: "A side-route skill for restructuring code safely: a refactor RFC and a tiny-commit migration path, hammered out through a detailed interview before any implementation.",
	},
	"Evans-Domain-Driven Design": {
		lesson: "One ubiquitous language, shared by code, docs, and conversation.",
		file: "ubiquitous-language/SKILL.md",
		fm: 'sources:\n  primary:\n    - "Domain-Driven Design — Eric Evans"\n  secondary:\n    - "Domain Storytelling — Hofer & Schwentner"\n    - "Living Documentation — Cyrille Martraire"',
		excerpt: "Define the domain model’s vocabulary. Each term in this glossary is a model element — changing a term here means changing the model and the code.",
	},
	"Humble & Farley-Continuous Delivery": {
		lesson: "Keep the mainline always releasable; merge in small, verified steps.",
		file: "pre-merge/SKILL.md",
		fm: 'sources:\n  secondary:\n    - "Continuous Delivery — Jez Humble & David Farley"\n    - "The Checklist Manifesto — Atul Gawande"\n    - "Release It! — Michael Nygard"\n    - "The Twelve-Factor App — Adam Wiggins"',
		excerpt: "Create a GitHub PR linking back to the PRD and slice issues, then review the full diff against the project’s architectural principles across 11 review dimensions.",
	},
	"Beck-XP Explained": {
		lesson: "Courage through feedback — short loops beat long plans.",
		file: "prototype/SKILL.md",
		fm: 'sources:\n  primary:\n    - "Extreme Programming Explained — Kent Beck"',
		excerpt: "Throwaway code that answers a question — LOGIC probes the state model, UI compares layout variants, FEASIBILITY discharges an Uncertain research assumption with a spike solution.",
	},
	"Pocock-Total TypeScript": {
		lesson: "Type-level discipline: inference first, narrowing over assertions.",
		file: "ts-audit/SKILL.md",
		fm: 'sources:\n  primary:\n    - "Total TypeScript — Matt Pocock"\n  secondary:\n    - "Testing Fundamentals — Kent C. Dodds"\n    - "Advanced Vitest Patterns — Epic Web Dev"\n    - "Mocking Techniques in Vitest — Epic Web Dev"',
		excerpt: "Covers type safety, generics, narrowing, branded types, discriminated unions, React patterns, type transformations, and testing — each finding grounded in a specific library reference.",
	},
};

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
	{ name: "Orientation", skills: ["help", "correct-course", "handoff"] },
	{ name: "Tooling", skills: ["init-pipeline", "setup-pre-commit", "setup-ralph-loop", "git-guardrails-claude-code"] },
];

export const repoUrl = "https://github.com/chrislacey89/skills";
export const installCommand = "npx skills@latest add chrislacey89/skills";
export const fullInstallCommand = "npx skills@latest add chrislacey89/skills --skill '*' --agent claude-code --global -y";
