-- Presentation for server-specific equipment bonuses, independent of current job.
return {
    bstshinychance = { key = 'BSTShinyChance', label = 'Shiny Chance Bonus', section = 'Pet', percent = true },
    bstreadytpkept = { key = 'BSTReadyTPKept', label = 'Ready TP Retained', section = 'Pet', percent = true },
    -- Saotome Domaru and Kabuto (sam_af_relic.sql), named as the item text names them.
    samchaintpbonus = { key = 'SAMChainTPBonus', label = 'Skill Chain TP Bonus', section = 'Ability' },
    samseigancountertp = { key = 'SAMSeiganCounterTP', label = 'TP Counter', section = 'Ability' },
    thirdeyecounterdamage = { key = 'ThirdEyeCounterDamage', label = 'Third Eye Counter Dmg.', section = 'Ability', percent = true },
};
