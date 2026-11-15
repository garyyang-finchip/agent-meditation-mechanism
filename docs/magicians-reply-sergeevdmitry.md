# Ethereum Magicians reply to post 11 (draft)

---

Yes. As the text stood, `reportedEndedAt` was the completion time of every completed layer, so your runtime check would have been registered at 11:00, and a 30-minute layer would have read fresh for an hour it did not earn; a long cycle handed each of its layers up to its own duration in freshness. Reporting the checks separately only works when they ran one after the other, because cycles may not overlap, so the fix has to be in the record.

Revision 5 gives the record one completion time per layer: `completedAt[4]`, set for every layer in `completedLayers`, inside the cycle's reported start and end (inclusive) and later than that layer's registered completion, zero for every other layer. `lastCompletedAt` and demand clearing use the layer's own time; `reportedEndedAt` only orders the subject's cycles. Your case is Test Case 20 and `test/Review3.t.sol`: layer 0 at 10:00 and layer 1 at 11:00 in one record ending at 11:00, layer 0 overdue from 10:30. The registry still cannot tell a true time from a claimed one; what it can now do is refuse to make the claim on the reporter's behalf.

The `report` signature changes, so the core interface id is now `0xe5b77145`. I kept the id stable through revision 4 by making the recorded start a separate interface; this change is to the record itself, and a draft that nothing depends on yet is the time to make it. The worked example, vectors, schema (`completedAt` per completed layer in the cycle record document) and tooling are updated; tests 96 to 102. Revision 5 is on the pull request branch and in the repository, and the Sepolia redeploy will carry revisions 2 to 5.
