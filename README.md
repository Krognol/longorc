# Long Orc

Discord bot writting in [Discordnim](https://github.com/Krognol/discordnim).

# ToDo

Documentation

# Commands

| Command       | Arg           | Desc  | Mod command |
| ------------- |:-------------:| :-----:| :----: |
| .!iroll      | integer number | Rolls a random integer between 0..n | false |
| .!froll      | floating point number | Rolls a random FPN between 0.0..n | false |
| .!d6 | -- | Rolls a 6 sided die | false |
| .!anime | name | Anilist.co entry on anime | false |
| .!manga | name | Anilist.co entry on manga | false |
| .!character | name | Anilist.co entry on character | false |
| .!urban | word | Urban dictionary definition of word | false |
| .!define | word | Wiktionary definition of word | false |
| .!userinfo | -- | User information | false |
| .!serverinfo | -- | Information about the server | false |
| .!status | -- | Bot status | false |
| .!enablewidget | -- | Enables the server widget | true |
| .!eval | code | Evaluates Nim code. Restricted to one liners | false |
| .!prune | amount | Deletes all N messages not older than 2 weeks | true |
| .!gfy | tag | Looks up a random Gfycat with [tag] | false |
| .!gfy tags | -- | Looks up popular Gfycat tags | false |
| .!gfy trending | -- | Looks up trending Gfycats | false |
| .!gfycat user | name | Looks up Gfycat user | false |
| .!wolfram | query | Wolfram\|Alpha query result | false |
| .!fm | username, or nothing | Looks up last.fm user's last played, and currently playing track. If no username is given takes from local cache | false |
| .!fm set | username | Sets a last.fm username in the local cache | false |
| .!fm collage | username, or nothing | Gets a collage of the users top played albums in the last week | false |
| .!fm topweekly | username, or nothing | Gets statistics of the users most played songs in the last week | false |