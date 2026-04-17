English | [한국어](why-lao.ko.md)

# LAO Pain Points

Date: 2026-03

------------------------------------------------------------------------

# 1. Overview

LAO is a system built to address structural problems in current AI
collaboration practices.

Today's AI collaboration is predominantly **chat-based**, while actual
work is **project-based**.

This structural mismatch creates several problems.

------------------------------------------------------------------------

# 2. Core Pain Points

## 2.1 Chat Does Not Lead to Execution

Current AI collaboration tools

-   ChatGPT
-   Claude
-   Cursor
-   Codex

These tools are mostly chat-based.

Problem

-   Many ideas get generated, but
-   They don't lead to execution.

Example

Idea discussion\
→ Good ideas\
→ Chat ends\
→ Work never executed

Core issue

Chat = Record\
Chat ≠ Execution

------------------------------------------------------------------------

## 2.2 Long Conversations Break Context

Long chats cause context collapse.

Symptoms

-   Conversation grows long
-   AI forgets earlier content
-   Topics scatter
-   Decisions get lost

Flow

Start → Clear discussion\
Middle → Branching ideas\
End → What were we doing?

Both AI and humans get confused.

------------------------------------------------------------------------

## 2.3 Work Gets Fragmented

AI collaboration spreads work across multiple locations.

Example

Chat\
Code\
Documents\
Ideas\
Experiments

Tools

ChatGPT\
Cursor\
Notion\
GitHub\
Slack

Problem

-   No one knows what was decided
-   No one knows what needs to be done
-   No one knows what's been completed

------------------------------------------------------------------------

## 2.4 AI Has No Role

Current AI collaboration structure

AI = General assistant

But real organizations are role-based.

Example roles

PM\
Developer\
Researcher\
Marketing

Without roles, AI suffers from

-   Repeated questions
-   No accountability structure
-   No decision flow

------------------------------------------------------------------------

## 2.5 No Project Structure

Current AI usage pattern

Chat 1\
Chat 2\
Chat 3

But actual work structure

Project ├ Meetings ├ Tasks └ Documents

Problem

-   Chats aren't connected to projects
-   No work history
-   No knowledge accumulation

------------------------------------------------------------------------

## 2.6 Multi-Provider Fragmentation

Users already use multiple AI providers simultaneously.

Providers in use

-   OpenAI (ChatGPT, GPT API)
-   Anthropic (Claude CLI, Claude API)
-   Google (Gemini)
-   Various open-source models

Problem

-   Conversations are separated per provider
-   Same project, different context per AI
-   No way to trace which AI reached which conclusion
-   Outputs across providers can't be integrated

Example

Claude CLI → SEO strategy discussion\
ChatGPT → Marketing copy writing\
Gemini → Data analysis\
→ Same project, but context is fragmented across all

------------------------------------------------------------------------

## 2.7 CLI Sessions Are Ephemeral

The problem intensifies when using AI via CLI.

Symptoms

-   Context is completely lost when sessions end
-   The same project discussion restarts from scratch each session
-   AI-generated ideas and decisions aren't structured into files
-   Work outputs scatter across the local file system

CLI-specific issues

-   Closing the terminal evaporates the conversation
-   Sharper disconnect between file-based work and dialogue
-   Even with history, search and structuring are impossible

------------------------------------------------------------------------

# 3. Key Insight

The biggest problem is this:

**Chat does not remember work.**

------------------------------------------------------------------------

# 4. Summary

LAO is not just a collaboration tool — it aims to be

**a layer that converts plans into AI-execution-friendly design
documents.**

Core transformation

Chat-based work → Structured design conversion

Role separation
* **LAO** = Design converter — organizes *what to build* and *how to
  deliver it*
* **Development AI** (Claude Code, Codex) = Implementer — converts the
  organized design into actual code

Output pipeline

Screen plan → Common reference document → Development design draft → Delivered to development AI via MCP
