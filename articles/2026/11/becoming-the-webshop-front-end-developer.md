---
title: "Becoming the webshop front-end developer, with a lot of AI help"
description: How AI helped a data developer contribute to a Shopify webshop, prepare a human handover, and connect owner edits with developer code without treating them as the same thing.
permalink: /articles/becoming-the-webshop-front-end-developer/
image: /assets/shopify-handover/shop-desktop-2026-11-07.png
---

<header class="article-header">
    <div class="article-header__inner">
        <p class="article-kicker">Issue 05 · AI-assisted Shopify development</p>
        <h1>Becoming the webshop front-end developer, with a lot of AI help</h1>
        <p class="article-deck">Helping with a Shopify webshop, preparing a human handover, and keeping owner edits and developer code working together.</p>
        <p class="article-date">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 2v4M17 2v4M3.5 9.5h17M5.5 4h13a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z"/></svg>
          <span><span class="visually-hidden">Published </span>26 November 2026</span>
        </p>
    </div>
</header>

<p class="article-summary">
  <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h16v13H8l-4 4V4Z"/><path d="M8 8h8M8 12h6"/></svg>
  <span><strong class="visually-hidden">In short: </strong>A(I)pparently, I am a front-end developer thanks to VS Code agents and the power of vibe coding.</span>
</p>

## Apparently, I do webshop front ends now

More accurately: AI helped me contribute outside my speciality, documentation made the work easier to inherit, and CI/CD had to respect two very different ways of editing the same shop. So, obvious fact about me: I am a nerd.

New fun fact about my nerdiness: I paint figurines.

I find the community painting sessions cathartic. And the community leaders needed help that I could support them with.

((Also note: Realism in my drawings and painting is still a work in progress. These last few weeks, I have spent an unreasonable amount of time trying to make a flower look recognisably like a poppy, rather than just an unspecified flower for a sinterklas gift. It failed but now it's like a 3 year old child coming home to present their picture of an unknown blob and telling their parent "it's a horse".))

I am a data boi. More backend than front end. My previous experience with Shopify was a long time ago, and the platform has changed A LOT ('sup fellow php'ers).

What had also changed was my ability to work with AI. AI made it possible for me to contribute before I had all the front-end expertise. I was learning Shopify as I went, but not as intimately as the systems I work with in my day-to-day job.

I'm being paid in exposure. :) Technically, if you're reading this, they're also getting free advertising out of it too.

So anyone reading: I am not claiming to have become an experienced front-end developer. AI helped me build a first iteration, and a more experienced developer could take it further. And he did: Wouter focused on attention to detail, performance and the mobile experience. It also let me do a favour for some really nice people who were stressed.

## Here is the shop

The public result is [the Pink Orc Studios webshop](https://shop.pinkorcstudios.com/).

This is a screenshot of the public homepage on **7 November 2026**. The site can change after this article is written.

<a href="https://shop.pinkorcstudios.com/"><img src="{{ '/assets/shopify-handover/shop-desktop-2026-11-07.png' | relative_url }}" alt="Desktop view of the Pink Orc Studios webshop homepage, with its pink header and painting-desk hero."></a>

The phone view is worth showing too. This still image also links to the real shop.

<a href="https://shop.pinkorcstudios.com/"><img src="{{ '/assets/shopify-handover/shop-mobile-2026-11-07.png' | relative_url }}" alt="Phone view of the Pink Orc Studios webshop homepage."></a>

I would have liked to embed the live website here. Shopify's response explicitly blocks other sites from framing it: `X-Frame-Options: DENY` and `frame-ancestors 'none'`. Hosting the article on GitHub Pages cannot override that. Screenshots will have to do.

You'll have to click the link yourself if you're curious.

## Code first did not mean replacing Shopify's approach

I started with a local HTML, CSS and JavaScript prototype so we could discuss the design without changing the store. The actual storefront work used Shopify's native theme approach: Liquid, CSS, JavaScript, JSON templates, reusable sections and snippets. Shopify still supplied products, cart, checkout and orders.

Basically, Shopify already had its own backend. Lotte and Axel did not need me to create a SQLite or NoSQL backend. That was not their requirement. This whole post is about how I made them a prototype for the layout and sped things up so we could meet their 1.5-week deadline.

## Two interfaces, one shop

So Axel and Lotte work in Shopify's graphical interface. They manage store content in the admin and change theme content and layout through the theme editor. Developers (myself and eventually Wouter) work in code, review changes and merge them into `main`.

If I only sent developer changes towards Shopify, the repository could fall behind the owners' saved settings. Worse, a later upload of old defaults could replace work they had already done in the GUI.

If I copied everything back from Shopify, I could accidentally treat theme editor output as permission to replace developer code.

I needed a forward channel and a backwards channel, with different ownership rules:

```text
Developer -> reviewed change -> main/theme/
                                |
                        forward: checked code
                                v
                       connected theme branch <-> Shopify theme editor <- Owner
                                |
                        reverse: owner-managed JSON
                                v
                            main/theme/
```

The connected branch has Shopify's theme files at its root. The source repository has them under `theme/`, alongside documentation, tests and tools. These channels map selected files between two layouts; they are not a blanket merge of the two branches.

## Automating the forward and reverse handoff from the GUI

Now both parties can work on their babies: the owners in the GUI, and the developers in code.

This is theme synchronization, not a backup of the entire business. So hopefully they have saved this baby somewhere too!

I wanted to make their lives easier by automating that handoff with CI/CD.

So both of them can now work towards the same result. The two directions share a concurrency group, so they do not run their updates at the same time. Both use checked source tooling, validate the combined theme, check that the remote branches have not changed underneath them, and stop on conflicting owner/developer changes. These are GitHub Actions workflow checks, rather than separate local Git hooks.

The loop prevention does need care. Shopify's own bot commits represent owner saves and must be processed. The synchronizer's own tagged commits should not bounce backwards and forwards forever. To make future problems easier to explore, I also set up an audit trail. For queued work, it distinguishes the triggering revision from the revision actually synchronized.

For a small business, the audit trail came in the form of a Git branch. I could set it up with a fancy open-source tool or a cloud provider, but this is a family-run business. That might be too complex or unaffordable. A bonus branch for the audit trail seemed sufficient: which direction ran, which revisions it used, what changed, and whether it updated, skipped or failed. It records metadata, not owner values or customer data.

That separate audit branch gives me (*cough* AI *cough*) somewhere to check when something goes wrong. Git history can help recover earlier tracked theme files, but the audit itself is not a backup or an automatic rollback. The owner JSON comes back into `main`; the audit branch stays separate.

A separate branch is also not a live-theme safety lock. This whole CI/CD approach is not a safety lock, and I do want to raise a red flag if you want to incorporate it at scale. It was really helpful for our scenario, with one or two people working on something at the same time, but I would not recommend copying it into a production environment without proper pipelines and testing. Those checks matter for a small live shop too. Think of this shared example as help for a "HOLY CRAP THEY NEED IT BY THE END OF THE WEEK AND I NEED YOUR HELP" prototype or proof of concept, not a ready-made production deployment.

That is why I am sharing the approach. Think carefully if you intend to install our automation directly onto somebody else's live shop.


## A GitHub Actions example you can inspect

The [standalone example]({{ '/examples/owner-developer-sync/' | relative_url }}) is deliberately a **read-only routing and ownership demo**, not the production synchronizer. It exercises both directions, preserves owner files in the forward plan, refuses conflicting reverse changes, and prints filenames and operations rather than content. It neither commits nor pushes.

So I had AI help create the workflow. The real GitHub Actions workflow gave our little cohort a way to work together without extra manual handoff steps; the shared demo is a smaller way to explain that approach.

It sped us up, is all. The developer still needs to know how to test the changes before they reach production.

So here is the hero you can borrow if you are panicking over a short deadline. The key part of its [workflow]({{ '/examples/owner-developer-sync/theme-sync-demo.yml' | relative_url }}) is:

{% raw %}
```yaml
on:
  push:
    branches: [main, theme-editor]
  workflow_dispatch:
    inputs:
      direction:
        type: choice
        options: [forward, reverse]
        default: forward

permissions:
  contents: read

concurrency:
  group: owner-developer-theme-sync
  cancel-in-progress: false

jobs:
  plan:
    runs-on: windows-latest
    env:
      SYNC_DIRECTION: ${{ github.event_name == 'workflow_dispatch' && inputs.direction || (github.ref == 'refs/heads/main' && 'forward' || 'reverse') }}
    steps:
      - uses: actions/checkout@v4
        with:
          ref: main
          persist-credentials: false
      - uses: actions/setup-node@v4
        with:
          node-version: '22'
      - run: node --test sync-demo.test.cjs
      - run: node sync-demo.cjs $env:SYNC_DIRECTION
        shell: pwsh
```
{% endraw %}

The missing step between a teaching demo and a live synchronizer is not "add a push command". It includes real revision baselines, schema and Theme Check validation, remote-freshness checks, reviewed permissions, audit durability and a release/rollback policy.

## Build it for the person coming next

From the beginning, I expected somebody with more front-end experience to step in. Wouter jumped in four or five days before the deadline. Knowing that he was coming shaped the repository.

The next person, and whatever AI they use, should not need my memory or a giant transcript to reconstruct the project. Wouter came equipped with Claude, and I did not want to waste either of our time on a long mutual onboarding.

He knew I had good intentions and was vibe-coding to the best of my ability. I knew he was a web developer who could take my output to the next level. I hoped he had tried his own vibe-coding projects too.

So I designed a handover that Wouter's AI, or another LLM, could read as project context. It was also a way to convey the conversations I had had with Lotte.

Here is a generic version of the structure, not a copy of the private shop repository:

```text
project/
  README.md
  .github/
    copilot-instructions.md
    prompts/
      discovery.prompt.md
      change.prompt.md
      review.prompt.md
    workflows/
  docs/
    project/       # requirements and status-labelled decisions
    developers/    # setup, AI startup and change workflow
    owners/        # GUI editing locations and approval steps
  prototype/       # design exploration, not the commerce backend
  theme/           # deployable Shopify theme source
  scripts/         # repeatable commands
  tests/           # behaviour and workflow checks
```

The important part is the responsibility of each folder.

The AI startup guide points to curated requirements and decisions. The prompts separate discovery, approved implementation and review. A change brief names the outcome, affected files, owner editing location, acceptance checks and exclusions.

The decisions also distinguish "requested", "proposed", "agreed" and "verified". Something said in a meeting is not automatically permission to implement it, and a passing structural check is not proof that the storefront works.

The prototype was AI helping me build a website on localhost. It allowed me to show Lotte what I was doing. The tools and working habits I use at work also helped me give the next person something more useful than "here is the code, good luck".

## Teaching the owner to use AI

The handover also needs to help a nontechnical owner work with AI.

The old developer reflex is often:

> Have you Googled it?

Lotte had very little knowledge of GitHub. She knew it existed and had an account, and that was enough to get started. I wanted to teach her a small handful of steps so she could take this on even after Wouter handed it back to her.

I gave her a 30-minute workshop: create a branch, have AI make a small change, stage the intended files, commit and push, then create a PR and tag Victoria.

Wouter later extended this to GitHub Issues so she could stop writing to one of us via WhatsApp. Clever guy, that one. Sometimes she would ask us questions.

I think a useful new first check is:

> Have you checked this with AI first?

Not as a way to dismiss somebody asking for help. Not because an AI answer must be right. As a way to help them arrive with a clearer question, an explanation to challenge and a next step they can understand.

For a nontechnical owner, I would teach a small, bounded routine:

1. **Show the symptom:** use a screenshot or the exact visible wording, without customer details or account secrets.
2. **Ask for an explanation first:** "What does this setting do, and is this a content change or a code change?"
3. **Keep the boundary explicit:** "Do not change, save or publish anything. Tell me what I can check in the GUI."
4. **Bring the uncertainty back:** share the AI's explanation, what you tried and what happened. Ask the developer to check anything unclear or consequential.

She was still learning, so Wouter and I worked around what she wanted. If you are nontechnical and have found your way here: firstly, hello. Secondly, let me help you learn how to get the most out of a project like this.

For example:

```text
I want to change the heading on this shop section.
Explain where an owner can edit it in the theme editor.
Use the project owner guide; do not guess a setting that is not documented.
Do not change files, save settings or publish anything.
If this needs code rather than a GUI change, tell me what to ask the developer.
```

This is a teaching prompt, not a claim that the AI knows every version of Shopify's interface. I want the owner to understand the next step, not blindly execute a confident answer.

Of course you can iterate with AI. I do it all the time. For me, one of the biggest skills is knowing how to test the output in a trustworthy manner.

They also do not have to ask AI about every routine task. A good owner guide and a familiar setting can be enough. Payments, orders, policies, permissions and publication still need the right human judgement.

## What the experienced developer (Wouter) added

After the weekend handover, the repository records further mobile layout work, owner-editable homepage controls, product-page and image improvements, Dutch translations, accessibility and performance changes, and fixes to Liquid and search behaviour. He also taught Lotte to use git issues for feedback, which I think was a clever move.

Those are later developer and collaborative improvements, not things I should quietly claim as my original work. Wouter did it. It was cool looking at all the git commits and PRs he did. The synchronization work also continued after the handover.

Us collaborating and vibe-coding on top of this makes the story better, not worse. I could get useful work started with AI, and a more experienced person could inherit it, challenge it and improve it. I will take it as a compliment that he didn't completely start from scratch.

## What I learned

The interesting part was not just generating a front end. I mean, it's pretty fucking cool to do three days' worth of front-end development and watch it go live and be used. Code-first development and owner-friendly editing are not opposing goals. The forward and reverse channels exist precisely because both matter.

For me, I am so much more confident. There are SO many small projects I have now kicked off in my day-to-day life. I am going to ride this AI wild west until it becomes less fun.

So anyway, I am 'technically' a front-end developer now. :) Looking forward to trying out your brushes Pink Orc! It's currently being delivered as we speak!

Also, here's [Wouter's GitHub page](https://github.com/wschaap91).
