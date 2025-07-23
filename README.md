# Buildkite Doom Example

[![Add to Buildkite](/.buildkite/add.svg)](https://buildkite.com/new)

Now you can play [Doom](https://www.chocolate-doom.org/wiki/index.php/Chocolate_Doom) on [Buildkite](https://buildkite.com) — or have AI play it for you!

![](https://github.com/user-attachments/assets/a62f386c-a462-412a-a7e7-3a2eeece4b39)

## How it works

This project runs Doom interactively in a Buildkite pipeline. It's playable in three modes:

1. **Manual**: You choose each move in the Buildkite dashboard, one step at a time
2. **Random**: The pipeline chooses the next move for you at random
3. **AI**: [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) analyzes the game to determine the best next move

Each new move adds a step to the running pipeline, and the game interface (a PNG animation) is updated in place in the Buildkite dashboard. Canceling the build ends the game.

## See it in action 

https://github.com/user-attachments/assets/5890f5e4-46ec-4bc9-a2dc-beda3fd48624

The pipeline for this project [is also fully public](https://buildkite.com/buildkite/doom-example). Have a look at [a few recent plays](https://buildkite.com/buildkite/doom-example/builds).

## Create your own

To create a playable Doom pipeline of your own, you'll need:

* **A Buildkite account** — you can [grab a free trial here](https://buildkite.com/signup)
* **Docker** installed locally to run the [Buildkite agent](https://buildkite.com/docs/agent/v3) (under Ubuntu, for easier setup of [ffmpeg](https://ffmpeg.org/) and [Chocolate Doom](https://www.chocolate-doom.org/wiki/index.php/Chocolate_Doom))
* **Optionally, an Anthropic API key** to play in AI mode with Claude (the game falls back to manual mode by default). You can get an API key by visiting the [Anthropic console](https://console.anthropic.com/settings/keys).

Follow these steps to get going:

1. [Fork this repository](https://github.com/buildkite/doom-example/fork) into your GitHub account.
1. [Create a new Buildkite pipeline](https://buildkite.com/new) and configure it to use your newly forked repo. Be sure to choose a self-hosted agent agent cluster, as you'll be running the Buildkite agent locally on your computer. 
1. If you're prompted to set up a GitHub webhook, click **Skip Webhook Setup**. (You'll be running these builds on demand.)
1. Navigate to **Agents** &raquo; **Your Cluster** &raquo; **Agent Tokens**.
1. Create a new agent token and copy it to your clipboard.  
1. Export your `BUILDKITE_AGENT_TOKEN` and `ANTHROPIC_API_KEY` as environment variables:

    ```bash
    export BUILDKITE_AGENT_TOKEN="${your_new_buildkite_agent_token}"
    export ANTHROPIC_API_KEY="${your_anthropic_api_key}"
    ```

    Again, don't worry if you don't have an Anthropic token; the pipeline defaults to manual mode automatically.

1. Start the Buildkite agent with Docker, passing these two environment variables:

    ```bash
    docker run -it --rm -e "ANTHROPIC_API_KEY" buildkite/agent:3-ubuntu start \
        --token "$BUILDKITE_AGENT_TOKEN" \
        --spawn 2
    ```

    Note that this [spawns](https://buildkite.com/docs/agent/v3/cli-start#spawn) two Buildkite agent processes — one for the Doom server (it's a long-running process), another to trigger each move step.

3. Navigate to **Pipelines** &raquo; **Doom Example**, trigger a build with the **New Build** button, and start playing!

## What's interesting about this?

Aside from just being a fun — if slightly weird (and potentially expensive — watch those tokens!) — way to play Doom, this project demonstrates a few key Buildkite features:

1. **Dynamic pipelines**: It uses Buildkite [dynamic pipelines](https://buildkite.com/docs/pipelines/configure/dynamic-pipelines) to capture player input at runtime, adding a step to the running pipeline for each move. Dynamic pipelines enable you to define flexible, reactive workflows that adjust to the conditions of your build environment.

1. **AI-driven CI/CD workflows**: In AI mode, it uses Claude to analyze the state of the game and build the pipeline accordingly. This shows how LLMs like Claude can be used to drive more intelligent software-delivery workflows.

### How it works

The pipeline starts by prompting you with a Buildkite [input step](https://buildkite.com/docs/pipelines/configure/step-types/input-step) to set the desired gameplay mode — manual, random, or AI-driven.

<img width="400" src="https://github.com/user-attachments/assets/d414d13d-ad52-4cbe-a24b-03d440f71230" />

Once the mode is selected, the pipeline moves on to the next step, spawning a Ruby program (`doom.rb`) that starts the server, captures the first few frames of the game, and uploads the frames as a PNG animation with a Buildkite [build annotation](https://buildkite.com/docs/apis/rest-api/annotations). It then loops indefinitely, waiting for "keypress events":

* In manual mode, it prompts with another input step that lets you choose what to do next — move forward, turn, fire, etc.

    <img width="400" src="https://github.com/user-attachments/assets/02278258-f395-40f4-9d55-55fcc444796c" />

* In random mode, it chooses the next move for you.

* In AI mode, it reads the last few frames of the game, then has Claude analyze them and decide how to move next, attaching a brief explanation as to why.

The selected move is recorded as a [Buildkite agent metadata](https://buildkite.com/docs/pipelines/configure/build-meta-data) key-value pair. On the next iteration, the most recent move is fetched and sent to the running game, and the process continues until the build is canceled (or the user runs out of Anthropic credits!).

## Contributing

Contributions welcome! As you'll see, Claude needs all the help it can get to up its Doom game.

## Special thanks

Extra special thanks to [@rianmcguire](https://github.com/rianmcguire), who created the original version of this project. :raised_hands: :green_heart:
