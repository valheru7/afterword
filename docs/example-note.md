---
title: "Northwind \u2013 engineering manager"
date: 2026-10-20T14:00-07:00
template: job-interview
participants: ["Priya Shah"]
tags: ["afterword", "job-interview"]
---

> A made-up interview, run through `afterword process` with the `job-interview` template. Everyone in it is fictional.

# Northwind – engineering manager

## Summary
You met Priya Shah, who manages Northwind's platform team, for what looks like a hiring manager interview. It was short and friendly. She covered your background and one behavioral question, then described the role and what comes next. The call ended on a positive note, with a technical round already planned.

## People
- **Priya Shah**: Manager of the platform team at Northwind, there about four years. She asked about scale ("How big was that service?") and root cause, so she likely wants concrete numbers and technical depth. She cares most about someone taking ownership of the job scheduler, whose original builder has left.
- **Marcus**: Recruiter, mentioned but not on the call. He'll reach out this week to schedule the technical interview.

## Questions they asked
1. **"Can you start by telling me a bit about yourself?"** You said you have about seven years in backend work, mostly Python and Postgres. At a logistics startup you owned the shipment tracking service and moved it from a nightly batch job to event streaming, so customers saw updates in seconds instead of the next morning.
2. **"How big was that service, roughly?"** About two million events a day at peak, with a team of four.
3. **"Tell me about a time something went wrong in production and how you handled it."** You described a Friday when the queue backed up and things were slow for a while. The team fixed it and added monitoring afterward. You said it was "kind of a team thing" and that you didn't remember all the details.
4. **"What was the root cause?"** A consumer got stuck on a bad message, and the team added a dead letter queue afterward.

## How the answers landed
- **Your intro worked well.** It was short and concrete, and it had a clear before-and-after ("seconds instead of the next morning"). When she asked about scale you answered with real numbers right away. Keep this version.
- **The production incident answer was the weakest part of the call.** It started with filler ("Um, so, yeah, there was one time, I think..."), had no specifics, and moved the credit and ownership away from you ("kind of a team thing, I don't remember all the details honestly"). This matters for a role where on-call and owning the scheduler are central. Before the next round, rebuild this story with:
  - **Situation:** when it happened, what "slow" meant (how long, how far behind, whether customers noticed).
  - **Your part:** how you found the stuck consumer and what you did first to stop the problem.
  - **Fix:** the dead letter queue, plus the alerts you added and what they watch.
  - **Result:** whether it happened again, and what you changed about how bad messages get handled.
  If you can't recall the details of this incident, pick another one you remember well and owned.
- **The root cause answer was solid, but it came too late.** "A consumer was stuck on a bad message, so we added a dead letter queue" is a good, clear answer. Lead with it next time so she doesn't have to pull it out of you.
- **Back up "I like that kind of cleanup work."** Her main goal for the first six months is owning an under-documented scheduler that someone else built. Have a concrete example ready of a time you took over or documented a system you didn't write. The technical panel may well ask about this.
- **The streaming migration is your strongest story.** Expect two engineers to go deeper on it: why you chose event streaming, which tools you used, how you handled ordering, duplicates and backfill, and how you cut over from the batch job.

## About the role
- **Team:** Platform team, managed by Priya.
- **Scope:** Owns the internal job scheduler and the deploy pipeline.
- **Six-month goal:** Take ownership of the scheduler. The person who built it left and it's under-documented.
- **Stack:** Python and Go on Kubernetes. Go and Kubernetes didn't come up in your background, so be ready to speak to them.
- **Location:** Hybrid, two days a week in the Denver office.
- **Hiring:** Two people this quarter.
- **On-call:** One week in six, with an on-call stipend. Pages are usually quiet, about two a week.
- **Not discussed:** Salary, the stipend amount, benefits, team size, and title or level.
- **Flags:**
  - Green: on-call is light and paid.
  - Worth asking about: inheriting an under-documented system with its builder gone is real risk. Ask how much support and time you'd get to ramp up.

## Questions I asked
- **What does on-call look like on the team?** One week in six, paid with a stipend, usually around two pages a week.
- **What would success look like in the first six months?** Taking ownership of the scheduler, which is under-documented since its builder left.

## Next steps
- **Recruiter:** Marcus will reach out this week to schedule the next round.
- **Next round:** A technical interview with two engineers from the platform team.
- **You promised:** To send Priya the architecture write-up for the shipment tracking service. You called it "the write-up I mentioned," but it doesn't come up earlier in this recording. You may have mentioned it before the recording started, or in an earlier conversation. Either way, send it soon, ideally with your thank-you note.
- **Prepare:**
  - A rebuilt incident story.
  - An example of taking over a system someone else built.
  - Go and Kubernetes talking points.
  - Questions about pay and the scheduler's current state, for later rounds.

## Thank-you note
Subject: Thank you, and the tracking service write-up

Hi Priya,

Thanks for talking with me on Tuesday. I enjoyed hearing about the platform team, especially the plan for someone to take ownership of the job scheduler. Getting an under-documented system understood, written down and reliable is work I really like, and it was helpful to hear that's what success looks like in the first six months.

As promised, I've attached the architecture write-up for the shipment tracking service, including the move from nightly batch to event streaming.

I'm looking forward to the technical interview and to hearing from Marcus.

Best,
[Your name]

## Transcript

[00:00:03] Them: Hi, thanks for making time today. I'm Priya Shah, I manage the platform team here at Northwind. I've been here about four years. Can you start by telling me a bit about yourself?

[00:00:16] Me: Sure. I'm a backend developer, mostly Python and Postgres, about seven years now. Most recently I was at a logistics startup where I owned the shipment tracking service. The big thing I did there was move it off a nightly batch job to event streaming, so customers saw updates in seconds instead of the next morning.

[00:00:39] Them: Nice. How big was that service, roughly?

[00:00:43] Me: Around two million events a day at peak. Team of four.

[00:00:49] Them: Great. Tell me about a time something went wrong in production and how you handled it.

[00:00:56] Me: Um, so, yeah, there was one time, I think it was a Friday, the queue backed up and, uh, things were slow for a while and we fixed it. We added some monitoring after. It was kind of a team thing, I don't remember all the details honestly.

[00:01:16] Them: Okay. What was the root cause?

[00:01:20] Me: I think a consumer was stuck on a bad message. We added a dead letter queue after that.

[00:01:28] Them: Got it. So a bit about the role. This team owns our internal job scheduler and the deploy pipeline. It's Python and Go, we're on Kubernetes, and it's hybrid, two days a week in the Denver office. We're hiring two people this quarter.

[00:01:46] Me: That sounds great. What does on-call look like on the team?

[00:01:51] Them: One week in six, and we pay an on-call stipend. Pages are usually quiet, maybe two a week.

[00:01:59] Me: And what would success look like in the first six months?

[00:02:05] Them: Honestly, taking ownership of the scheduler. The person who built it left, and it's under-documented.

[00:02:12] Me: Makes sense. I like that kind of cleanup work.

[00:02:17] Them: Good to hear. Next step would be a technical interview with two engineers from the team. Our recruiter, Marcus, will reach out this week to schedule it. Anything else?

[00:02:29] Me: No, I think that's it. I'll send over the architecture write-up I mentioned for the tracking service.

[00:02:37] Them: Perfect. Thanks, talk soon.
