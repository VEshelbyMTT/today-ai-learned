---
title: "Using AI for visuals: dashboards and complex visualisations"
description: My first work baby, a fictional player-movement map, and a little help from AI to turn it into something you can play with.
permalink: /articles/using-ai-for-visuals-dashboards-and-complex-visualisations/
---

<!-- Publishing: keep all telemetry, players, coordinates, and map areas fictional. -->

<header class="article-header">
    <div class="article-header__inner">
        <p class="article-kicker">Issue 04 · Interactive dashboards</p>
        <h1>Using AI for visuals: dashboards and complex visualisations</h1>
        <p class="article-deck">My first work baby, a fictional player-movement map, and a little help from AI to turn it into something you can play with.</p>
        <p class="article-date">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 2v4M17 2v4M3.5 9.5h17M5.5 4h13a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z"/></svg>
          <span><span class="visually-hidden">Published </span>16 October 2026</span>
        </p>
    </div>
</header>

<p class="article-summary">
  <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h16v13H8l-4 4V4Z"/><path d="M8 8h8M8 12h6"/></svg>
  <span><strong class="visually-hidden">In short: </strong>I used AI to help turn player movement data into interactive maps and dashboards. It was friggen cool. Here's a fictional version you can play with, how we got to this dashboard, and a few things I'd check before trusting all the pretty colours.</span>
</p>

## From diagrams to interactive visuals

Last week, I used Mermaid to help explain something complicated. This week, we have little players running around a map. Naturally.

One of my very first projects at Mojang was a proof of concept heatmap for exploring player movement. My first work baby in the gaming industry. I am very proud of it.

When I started, I had no idea I'd be helping get it into Databricks as an app and dashboard eight months later, and speed running this all in the week of launch. It involved changing requirements, messy data, plenty of digging, and finding the right people to confirm that what I was seeing actually made sense. AI helped me move through the implementation more quickly. I had a very happy time investigating the puzzle.

The team wanted to understand how testers explored the world: where they went, how they returned to base, whether they found loot, and what the speed runners were getting up to. Movement was one piece of that picture; questions about deaths, loot, or performance needed the relevant data alongside it.

I look back on that project fondly. It reminded me just how fun data analysis can be. Explaining the whole thing, on the other hand: bloody complex.

So, here's my compromise for sharing it: an entirely fictional world, nine fake players, ten minutes of movement, and a dashboard you can have a play with. All the coordinates and areas are made up. The real telemetry and game map stay at work.

And yes, I'm absolutely using this as an excuse to show off my work baby.

## Try it: the Player Observatory

Meet the Player Observatory. Press Play and let the little players loose. You can also open the full page if you'd like more room.

<p><a href="{{ '/examples/player-observatory/observatory/' | relative_url }}" target="_blank" rel="noopener">Open the full Player Observatory</a></p>

<iframe id="player-observatory" src="{{ '/examples/player-observatory/observatory/' | relative_url }}?embedded" title="Player Observatory: interactive fictional player movement replay" loading="lazy" width="100%" height="1600" style="display: block; width: 100%; border: 0; border-radius: 12px;"></iframe>

<script>
(() => { const frame = document.getElementById("player-observatory"); window.addEventListener("message", event => { if (event.origin !== window.location.origin || event.source !== frame.contentWindow) return; if (event.data?.type !== "tail-observatory-height") return; const height = event.data.height; if (Number.isFinite(height) && height >= 500 && height <= 4000) frame.style.height = `${height + 2}px`; }); })();
</script>

Here's a little investigation to try:

1. Drag the timeline to **05:00**. Where has everyone wandered off to?
2. Leave one player selected in the **party roster**, then scrub back and forward. Following one journey makes it much easier to see how they got somewhere.
3. Select everyone again and switch to **Density**. Which parts of those individual journeys can you still see once they're all piled together?
4. Select an area to check its visitors and dwelling samples. A bright patch can include repeated samples from the same player.
5. Open **Behind the visual** if you want the definitions or a CSV of the records behind your selection. Have a dig.

The numbers follow your selected players from the start of the session up to the timeline cursor. Area visits use samples where a player is dwelling in an area. Density counts recorded positions, including travel, so one player hanging around can add plenty of colour. Distance adds up the straight-line steps between recorded positions, in fictional map units.

This little world only models movement. Any theories about loot, deaths, or why someone chose a route will have to wait for another dataset.

## How this became a dashboard

The Python version started with a fictional data generator, a notebook, and Plotly visuals. There's also a Streamlit app for selecting players, filtering time, changing the trails, and downloading the data.

Then I wanted to see how far we could take the presentation. My request to AI was essentially: can we make a really cool interactive dashboard that feels like high-quality engineering from a gaming perspective?

We talked through upgrading Streamlit or building a separate browser experience. I wanted a separate page that could sit inside this article, and a local preview so I could actually look at it before deciding what came next.

AI built the HTML, CSS, and JavaScript version you see above, using the same fictional CSV;  the internet started in HTML, and AI returns back to its roots. That gave us room to play with the map, replay controls, player roster, and colours together. The first preview made the idea much easier to react to. It's easier to say what you want changed when there's something in front of you.

For this example, the browser loads a small file and does the work locally. You can explore it without setting up Databricks or running Python. If you want to adapt the analysis in Python, [the example guide]({{ '/examples/player-observatory/' | relative_url }}) links to the Streamlit app, notebook, and source.

The fake movement also needed a little care. Everyone starts at spawn, pauses in areas, and walks along connected routes at a bounded speed. The generator uses a graph-based semi-Markov walk. My thesis is returning!! We get 1,089 position samples, taken every five seconds, with repeatable routes so we can check the same example again.

Each player keeps their own colour, with an outlined position marker and a short trail. That gives your eyes a fighting chance of following them around.

## The digging behind the pretty colours

The real project took about two months of digging, vibe coding, and asking questions. The data was in beta, the map was still changing, and the coordinates needed translating between what the game used and what appeared in telemetry. Even working out which axes I was looking at took investigation. Hello X,Y. Or X,Z. Right.

This is the part I really enjoy. I figured out what the coordinates meant, where they landed in the world, and why they looked different. Then I found people who could confirm the pieces. I still drew things on paper.

One of my most useful checks was following a single beta tester. I'd ask a game designer where spawn was and where an area should be. They shared the map with me of where it should be, then I would check whether the movement followed that branch. There were a lot of situations at the start where we would both scratch our head figuring out why the points weren't lining up.  Designing that translation through the algorithm was the first major breakthrough and then, visualising it indicated that the beta data of the coordinates were flipped from the world map, you as a player, see in game so I needed to also address that. If the coordinates were flipped or something didn't line up, that small journey gave me somewhere to start.

If you're making your own version, these are the bits I'd steal:

- **Pick one question first.** "Where did this player go?" gives you something specific to build and check.
- **Follow one record all the way through.** For me, that meant one player, their coordinates, and a route someone familiar with the world could recognise.
- **Ask what each colour and number means.** Repeated positions, different players, and time spent can tell different stories. Decide which one you're showing.
- **Check the boring bits too.** In this example, browser tests checked the totals against the CSV, player filters, replay controls, downloads, and mobile layouts. A shiny interface still needs numbers you can trace.
- **Befriend someone in the trenches.** A game developer helped me find two bits of information and translate how they fitted together.
- **Give someone a working version to react to.** Ask what they'd want to explore, collect feedback, and, as is tradition... iterate.

Scale deserves its own thought. Nine little players are lovely to animate. A launch week's worth of players needed filtering and aggregation, plus decisions about how much data reaches the screen. Spark and a datalake can help with processing; the visual still needs to stay usable.

## Go make something cool

If you've got an analysis sitting in a notebook, try asking AI to turn one useful part into something interactive. Tell it who will use it, what they want to explore, and which tools or hosting options you have. Start with a local preview and see what you think.

That's what I enjoyed here: I had a map, got curious about what else we could do with it, and now there are little players wandering around inside my article.

Very happy with that.

Note: Human stories and waffle, with AI helping on the editing and implementation. AI won this round.

#TodayAILearned #VSCode #ArtificialIntelligence #Streamlit #DataVisualisation
