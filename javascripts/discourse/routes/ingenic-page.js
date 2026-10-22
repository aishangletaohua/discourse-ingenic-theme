import DiscourseRoute from "discourse/routes/discourse";

/**
 * One standalone page, named by its slug.
 *
 * The slug is the whole route model: there is nothing else to load, because
 * the page's address is its identity. The component fetches the page itself,
 * the same way the other plugin readers do, so a language switch re-requests
 * the same slug in the new language rather than reloading the route.
 */
export default class IngenicPageRoute extends DiscourseRoute {
  model(params) {
    return params.slug;
  }
}
