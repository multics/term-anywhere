# Project development rules

- Complete one feature at a time.
- For each feature, run the relevant tests and checks, deploy the changed app to the target devices, then commit and push it.
- Use one commit per feature. Do not combine unrelated features in one commit.
- Update requirements, design notes, and validation evidence with the feature they describe.
- Distinguish draft code, passed tests, installed builds, and verified runtime behavior. Do not report a feature as delivered before deployment.
- Track active requirements and incomplete checks in docs/DELIVERY_PLAN.md. A new request adds to the plan unless the user explicitly replaces an earlier requirement.
- Keep the implementation small. Use native Apple controls and avoid extra frameworks or services without a concrete need.
