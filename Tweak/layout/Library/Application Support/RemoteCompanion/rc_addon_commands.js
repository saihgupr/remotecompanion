// How an add-on command reads: its add-on and action, the options it chooses, and the typed input.
// The same rules as the tweak (Tweak/RCAddOns.m: rcao_match_action, rcao_split_words), shared by the
// app (RCAddOnCatalog, through JavaScriptCore) and the Web UI (served as /rc_addon_commands.js), so
// there is one copy outside the tweak. tools/addon-lint-parity.py checks it against the tweak's
// "addons parse". addOns is the tweak's catalog: [{ id, actions: [{ command, options, input }] }].
var RCAddOnCommands = (function () {
  'use strict';

  function words(text) {
    return String(text == null ? '' : text).trim().split(/\s+/).filter(function (w) { return w.length > 0; });
  }

  function lower(text) {
    return String(text).toLowerCase();
  }

  // The action a command names: { addOn: index, action: index, rest: [words after the action's own] },
  // or null. The longest action command that fits wins.
  function match(addOns, command) {
    var w = words(command);
    if (w.length < 2) return null;
    for (var a = 0; a < (addOns || []).length; a++) {
      if (addOns[a].id !== lower(w[0])) continue;
      var actions = addOns[a].actions || [];
      var best = -1, length = 0;
      for (var i = 0; i < actions.length; i++) {
        var cw = String(actions[i].command || '').split(' ');
        if (cw.length > w.length - 1 || cw.length <= length) continue;
        var same = true;
        for (var j = 0; j < cw.length && same; j++) same = lower(w[j + 1]) === cw[j];
        if (same) { best = i; length = cw.length; }
      }
      return best < 0 ? null : { addOn: a, action: best, rest: w.slice(1 + length) };
    }
    return null;
  }

  // The option and choice a word picks, or null
  function choiceFor(action, word) {
    var options = action.options || [];
    for (var i = 0; i < options.length; i++) {
      var choices = options[i].choices || [];
      for (var j = 0; j < choices.length; j++) {
        if (lower(choices[j].word) === lower(word)) return { option: options[i], choice: choices[j] };
      }
    }
    return null;
  }

  // The words after an action's own: choice words first, at most one per option; the input starts at
  // the first other word, or after "--". An option that another option's choice skips (skipWhen) is
  // dropped, as the options screen hides it.
  // { choices: { option id: word }, input: text or null, skipped: [option ids] }
  function split(action, rest) {
    var chosen = {}, next = 0;
    for (; next < rest.length; next++) {
      if (rest[next] === '--') { next++; break; }
      var found = choiceFor(action, rest[next]);
      if (!found || chosen.hasOwnProperty(found.option.id)) break;
      chosen[found.option.id] = found.choice.word;
    }
    var skipped = [];
    (action.options || []).forEach(function (option) {
      if (!chosen.hasOwnProperty(option.id) || !option.skipWhen) return;
      for (var other in option.skipWhen) {
        if (chosen.hasOwnProperty(other) && lower(chosen[other]) === lower(option.skipWhen[other])) {
          skipped.push(option.id);
          return;
        }
      }
    });
    skipped.forEach(function (id) { delete chosen[id]; });
    return { choices: chosen, input: next < rest.length ? rest.slice(next).join(' ') : null, skipped: skipped };
  }

  // Typed input as it goes in a command: "--" in front when it starts with a choice word (or "--"),
  // so it's read as text. null when empty.
  function inputWords(action, text) {
    var trimmed = String(text == null ? '' : text).trim();
    if (!trimmed) return null;
    var first = words(trimmed)[0];
    return first === '--' || choiceFor(action, first) ? '-- ' + trimmed : trimmed;
  }

  return { match: match, split: split, inputWords: inputWords, choiceFor: choiceFor, words: words };
})();
