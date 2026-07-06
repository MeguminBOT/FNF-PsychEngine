--[[
	Example custom note -- PSYCHLUA (classic API)
	=============================================
	No legacy note internals: no game.notes, no game.unspawnNotes, no new Note(), no setPropertyFromGroup.
	v2 note model (what the API touches here):
	  - `spawnNote` is the note currently being spawned (an ActiveNote), valid ONLY inside onSpawnNote.
	  - `spawnNote.data` = the note's data (column, type, hitHealth, ...); read at judge time.
	  - `spawnNote.head` = the note's drawable (NoteSprite): multAlpha, multSpeed, ...
]]

function onCreate()
	precacheImage('MYNOTE_assets', true) -- image, gpuCaching?
end

function onSpawnNote(id, direction, noteType, isSustainNote, strumTime, mustPress)
	if noteType == 'Custom Note' then
		setNoteTexture('MYNOTE_assets') -- This is for spritesheet based notes.
		setNoteColorable(false) -- Enables or disables coloring for this note
		setProperty('spawnNote.head.multAlpha', 0.6)
		setProperty('spawnNote.data.hitHealth', 0.08)
	end
end

function goodNoteHit(id, direction, noteType, isSustainNote)
	if noteType == 'Custom Note' then
		playSound('example-hit', 0.7)
		cameraShake('game', 0.006, 0.12)
		playAnim('boyfriend', 'hey', true)
	end
end

function noteMiss(id, direction, noteType, isSustainNote)
	if noteType == 'Custom Note' then
		setHealth(getHealth() - 0.06)
		cameraShake('game', 0.01, 0.15)
	end
end
