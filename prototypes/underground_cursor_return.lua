-- Follow the player's existing clear-cursor binding, including a rebound Q.
-- This does not add a new key binding or consume the game's normal action.
data:extend{{
    type='custom-input',
    name='the-cave-clear-underground-cursor',
    key_sequence='',
    linked_game_control='clear-cursor',
    consuming='none',
}}
