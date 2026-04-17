[English](why-lao.md) | 한국어

# LAO Pain Points

Date: 2026-03

------------------------------------------------------------------------

# 1. Overview

LAO는 현재 AI 협업 방식에서 발생하는 구조적 문제를 해결하기 위해
만들어진 시스템이다.

현재 AI 협업은 대부분 **채팅 중심**으로 이루어지고 있으며,\
실제 작업은 **프로젝트 중심**으로 이루어진다.

이 구조적 불일치가 여러 문제를 만든다.

------------------------------------------------------------------------

# 2. Core Pain Points

## 2.1 Chat Does Not Lead to Execution

현재 AI 협업 도구

-   ChatGPT
-   Claude
-   Cursor
-   Codex

이 도구들은 대부분 채팅 기반이다.

문제

-   아이디어는 많이 나오지만
-   실행으로 이어지지 않는다.

예

Idea discussion\
→ Good ideas\
→ Chat ends\
→ Work never executed

핵심 문제

Chat = Record\
Chat ≠ Execution

------------------------------------------------------------------------

## 2.2 Long Conversations Break Context

긴 채팅은 컨텍스트 붕괴를 일으킨다.

현상

-   대화 길어짐
-   AI가 이전 내용을 잊음
-   주제가 분산됨
-   결정 사항이 사라짐

흐름

Start → Clear discussion\
Middle → Branching ideas\
End → What were we doing?

AI와 사람 모두 혼란을 겪는다.

------------------------------------------------------------------------

## 2.3 Work Gets Fragmented

AI 협업 시 작업이 여러 곳에 분산된다.

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

문제

-   무엇이 결정되었는지 모름
-   무엇을 해야 하는지 모름
-   무엇이 완료되었는지 모름

------------------------------------------------------------------------

## 2.4 AI Has No Role

현재 AI 협업 구조

AI = General assistant

하지만 실제 조직은 역할 기반이다.

Example roles

PM\
Developer\
Researcher\
Marketing

AI에게 역할이 없으면

-   같은 질문 반복
-   책임 구조 없음
-   의사결정 흐름 없음

------------------------------------------------------------------------

## 2.5 No Project Structure

현재 AI 사용 방식

Chat 1\
Chat 2\
Chat 3

하지만 실제 작업 구조

Project ├ Meetings ├ Tasks └ Documents

문제

-   채팅이 프로젝트와 연결되지 않음
-   작업 히스토리 없음
-   지식 축적 불가능

------------------------------------------------------------------------

## 2.6 Multi-Provider Fragmentation

사용자는 이미 여러 AI 프로바이더를 동시에 사용하고 있다.

사용 중인 프로바이더

-   OpenAI (ChatGPT, GPT API)
-   Anthropic (Claude CLI, Claude API)
-   Google (Gemini)
-   기타 오픈소스 모델

문제

-   프로바이더마다 대화가 분리됨
-   같은 프로젝트인데 AI별로 맥락이 다름
-   어떤 AI가 어떤 결론을 냈는지 추적 불가
-   프로바이더 간 결과물을 통합할 수 없음

예

Claude CLI → SEO 전략 논의\
ChatGPT → 마케팅 카피 작성\
Gemini → 데이터 분석\
→ 같은 프로젝트인데 맥락이 모두 분리됨

------------------------------------------------------------------------

## 2.7 CLI Sessions Are Ephemeral

AI를 CLI로 사용하는 환경에서는 문제가 더 심각하다.

현상

-   세션이 끊기면 맥락이 완전히 소실됨
-   같은 프로젝트 논의를 매번 새 세션에서 처음부터 반복
-   AI가 낸 아이디어와 결정이 파일로 구조화되지 않음
-   작업 결과물이 로컬 파일 시스템에 흩어짐

CLI 특유의 문제

-   터미널 닫으면 대화 증발
-   파일 기반 작업과 대화의 단절이 더 심함
-   히스토리가 있어도 검색과 구조화가 불가능

------------------------------------------------------------------------

# 3. Key Insight

가장 큰 문제는 다음과 같다.

**Chat does not remember work.**

------------------------------------------------------------------------

# 4. Summary

LAO는 단순한 협업 도구가 아니라

**기획서를 AI 실행 친화적인 설계서로 바꿔주는 레이어**

를 목표로 한다.

핵심 변화

Chat-based work → 구조화된 설계 전환

역할 분리
* **LAO** = 설계 전환기 — *무엇을 만들지*와 *어떻게 전달할지*를 정리
* **개발 AI** (Claude Code, Codex) = 구현기 — 정리된 설계를 실제 코드로 구현

산출물 파이프라인

화면 기획서 → 공통 기준 문서 → 개발 설계서 초안 → MCP로 개발 AI에 전달
