import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { getOwner } from "@ember/owner";
import { themePrefix } from "virtual:theme";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/ingenic/bounties";

/**
 * The bounty field in the composer, before a topic exists.
 *
 * A bounty names a topic, so it cannot be opened until one does. What the field
 * does is remember the amount and open the offer the moment the topic is
 * created, which is one request the member never has to think about. The same
 * offer can still be opened afterwards from the topic page; this is the path
 * for someone who already knows, while writing, that the question is worth
 * paying for.
 *
 * Two refusals are answered in the composer rather than after posting:
 *
 *   more points than the member has   a dialog with the two honest choices —
 *                                     adjust it, or post without one. Posting
 *                                     without a bounty is the default the forum
 *                                     would fall back to anyway, so it is
 *                                     offered as a button rather than as a
 *                                     silent drop.
 *   more than the forum's ceiling     an inline sentence, because the member
 *                                     is not losing anything by editing the
 *                                     number — there is nothing to decide.
 *
 * The topic is posted first and the bounty second. If the second step fails the
 * member is told so plainly: the topic exists, and they can open the offer from
 * it with the same amount. That step is taken by the layout initializer rather
 * than here, because the composer closes — and this field with it — before
 * `composer:created-post` is fired. All this component leaves behind is the
 * amount, on the composer model, for the initializer to find.
 */
export default class IngenicComposerBounty extends Component {
  // The topic page carries the same payload, but none of it is on the composer,
  // and the floor, ceiling and balance are what decide whether the field can be
  // used at all — so they are asked for once, when the composer opens.
  @tracked limits = null;
  @tracked amount = "";
  @tracked error = null;

  @tracked checking = false;

  constructor(owner, args) {
    super(owner, args);

    this.dialog = getOwner(this).lookup("service:dialog");
    this.#load();
  }

  get model() {
    return this.args.outletArgs?.model;
  }

  // Only a new topic carries one. A reply has no topic to attach to that the
  // member owns, and an edit is a different question with its own page.
  get visible() {
    return (
      this.model?.creatingTopic === true &&
      this.limits?.available === true &&
      this.limits?.signed_in === true
    );
  }

  get points() {
    return Number.parseInt(this.amount, 10) || 0;
  }

  get max() {
    return Math.min(this.limits?.max_points ?? 0, this.limits?.balance ?? 0);
  }

  get overBalance() {
    return this.points > 0 && this.points > (this.limits?.balance ?? 0);
  }

  get hint() {
    if (this.overBalance) {
      return i18n(themePrefix("ingenic.bounties.composer_over_hint"), {
        balance: this.limits.balance,
      });
    }

    return i18n(themePrefix("ingenic.bounties.composer_hint"));
  }

  @action
  setAmount(event) {
    this.amount = event.target.value;
    this.error = null;
    this.#remember();
  }

  // The composer model outlives the field — the field is torn down when the
  // composer closes, a moment before the topic's creation is announced — so the
  // amount is parked there for the initializer that opens the bounty.
  #remember() {
    if (this.model) {
      this.model.ingenicBountyPoints = this.points;
    }
  }

  // Checked when the box is left rather than on every keystroke: a member
  // typing "150" passes through "1", and a dialog at "1" would be noise.
  @action
  async checkAmount() {
    if (this.checking || !this.limits) {
      return;
    }

    const points = this.points;
    if (!points) {
      return;
    }

    if (points > this.limits.balance) {
      this.checking = true;
      try {
        const waiver = await this.dialog.confirm({
          title: i18n(themePrefix("ingenic.bounties.composer_over_title")),
          message: i18n(themePrefix("ingenic.bounties.composer_over_body"), {
            balance: this.limits.balance,
            points,
          }),
          // These are keys, not text: the dialog's buttons translate their
          // labels themselves, so handing them an already-translated sentence
          // makes them look it up again and render "[en.…]" instead.
          confirmButtonLabel: themePrefix(
            "ingenic.bounties.composer_post_without"
          ),
          cancelButtonLabel: themePrefix(
            "ingenic.bounties.composer_keep_editing"
          ),
        });

        if (waiver) {
          this.amount = "";
          this.#remember();
          this.#saveComposer();
        }
      } finally {
        this.checking = false;
      }
      return;
    }

    if (points > this.limits.max_points) {
      this.error = i18n(themePrefix("ingenic.bounties.composer_ceiling"), {
        max: this.limits.max_points,
      });
    }
  }

  #saveComposer() {
    getOwner(this).lookup("service:composer")?.save();
  }

  async #load() {
    try {
      const response = await ajax(ENDPOINT);
      this.limits = {
        available: response.available === true && response.enabled !== false,
        signed_in: response.signed_in === true,
        min_points: response.min_points ?? 1,
        max_points: response.max_points ?? 0,
        balance: response.balance ?? 0,
      };
    } catch {
      // Left unset, and the field is not drawn. The server would refuse an
      // offer anyway; an input that cannot be used is worse than none.
    }
  }

  <template>
    {{#if this.visible}}
      <div class="ingenic-composer-bounty">
        <label class="ingenic-composer-bounty__field">
          <span class="ingenic-composer-bounty__label">
            {{dIcon "gift"}}
            {{i18n (themePrefix "ingenic.bounties.composer_label")}}
          </span>
          <input
            type="number"
            name="ingenic-bounty-points"
            min={{this.limits.min_points}}
            max={{this.max}}
            value={{this.amount}}
            placeholder={{i18n
              (themePrefix "ingenic.bounties.composer_placeholder")
            }}
            {{on "input" this.setAmount}}
            {{on "blur" this.checkAmount}}
          />
        </label>

        <p class="ingenic-composer-bounty__hint">
          {{this.hint}}
          {{i18n
            (themePrefix "ingenic.bounties.composer_balance")
            points=this.limits.balance
          }}
        </p>

        {{#if this.error}}
          <p class="ingenic-composer-bounty__error">{{this.error}}</p>
        {{/if}}
      </div>
    {{/if}}
  </template>
}
