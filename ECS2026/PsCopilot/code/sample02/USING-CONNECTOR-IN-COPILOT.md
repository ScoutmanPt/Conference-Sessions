# Using Connector Data in Copilot Chat

A Copilot connector does not force Copilot to query the connector for every answer.
It makes your external data available as a grounding source through Microsoft 365
Search and Microsoft Graph. Copilot then decides whether to retrieve that source
based on the prompt, permissions, ranking, freshness, and whether general model
knowledge already seems sufficient.

For example, this prompt is unlikely to prove that the connector is being used:

```text
What is the capital of France?
```

The model already knows that answer. It may respond from general knowledge instead
of retrieving the REST Countries connector item.

## Better Prompt Patterns

Use prompts that explicitly ask for work or connected content:

```text
Using Microsoft 365 work content only, what country data do we have for France?
```

```text
Search my organization's connected content for France and summarize the result.
```

```text
Use the REST Countries connector content, not general web knowledge. What fields are available for Portugal?
```

```text
From our connected REST Countries data, list countries in Western Europe with their capital and population.
```

```text
Find the connected item for Denmark and cite the source.
```

```text
Use only connected work data. What does the REST Countries connector say about Denmark? Include citations.
```

If Copilot answers with citations to the connector item, it used the connector.
If it answers without citations, it may be using general model knowledge.

## Proving the Connector Is Used

For a demo, avoid asking about facts the model already knows. Add a unique marker
or internal phrase to the indexed content, re-import the data, and ask about that
marker.

Example marker:

```text
RESTCOUNTRIES_CONNECTOR_2026
```

Then ask:

```text
Use only work content. What is RESTCOUNTRIES_CONNECTOR_2026?
```

If Copilot can answer and cite the connector item, the answer came from your
connector data.

## Improve the Indexed Body Content

The REST Countries import script should index a useful natural-language body,
not only the country name.

Weak grounding:

```powershell
content = @{
  value = $_.Name
  type  = 'text'
}
```

Better grounding:

```powershell
content = @{
  value = "$($_.Name) is in $($_.Region), $($_.Subregion). Its capital is $($_.Capital). Population is $($_.Population). Languages: $($_.Languages). Currencies: $($_.Currencies). Border countries: $($_.Borders). Demo marker: RESTCOUNTRIES_CONNECTOR_2026."
  type  = 'text'
}
```

The schema properties are useful for search, filtering, result templates, and
retrieval. The `content.value` field gives Copilot richer text to retrieve,
summarize, and cite in chat.

## Key Idea

Connectors are retrieval sources, not command channels. To make Copilot use them:

- Ask source-bound questions.
- Mention work content or connected content.
- Require citations.
- Use unique test phrases when validating.
- Index natural-language body content that contains the facts Copilot should use.
