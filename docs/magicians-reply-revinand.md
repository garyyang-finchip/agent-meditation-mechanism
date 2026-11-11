# Ethereum Magicians reply to post 6 (draft)

---

Thanks, and yes, that is a hole revision 2 opened. The demand puts an unscheduled layer on the clock, but nothing stopped the subject from taking the layer out from under it, and the outcome you describe is the worst of both readings: the layer reads `OVERDUE` and no completion can be accepted under the policy that dropped it.

Revision 3 takes your rule. A new policy version must keep every layer with an outstanding demand in `supportedLayers`; `setPolicy` rejects a version that drops one (`LayerUnderObligation(layer)`) until the demand is completed or withdrawn. Other policy changes go through while the demand is outstanding. The demand is the controller's instrument, so clearing it stays with a qualifying completion or with the controller through `withdrawDemand`, never with a policy change by the subject.

The same check now covers a case of the same shape that the text had not addressed: a layer the floor requires also has to stay in `supportedLayers`. Without that, the subject could drop a floor-required layer, the floor would keep it required, `report()` would refuse it, and it would be overdue forever for exactly your reason. The other direction is unchanged and now stated: a floor may require a layer the policy does not yet support, the layer is judged, and the subject's next policy version has to support it. Rationale and Security Considerations carry the reasoning, Test Case 17 the behaviour.

Tests: your sequence (demand on unscheduled layer 3, policy dropping layer 3, expected revert), the withdrawal path, the floor variant and a floor on a never-supported layer; 74 to 78. Interface id unchanged, one more registry error. Revision 3 is on the pull request branch and in the repository, and the Sepolia redeploy will carry revisions 2 and 3 together.
