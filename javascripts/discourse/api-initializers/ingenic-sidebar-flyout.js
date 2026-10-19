import { apiInitializer } from "discourse/lib/api";
import IngenicSidebarFlyout from "../components/ingenic-sidebar-flyout";

/**
 * Hangs the sub-category flyout inside the sidebar.
 *
 * `after-sidebar-sections` is the one public outlet that sits inside the
 * sidebar and outside every link, which is what the flyout needs: its panels
 * carry links of their own, so they cannot be nested in a sidebar row, and
 * they must scroll and clip with the column rather than float over the whole
 * page. Rendering the component here leaves core's sidebar untouched — the
 * rows, filter, collapse and mobile drawer all keep working, and the component
 * only listens for a pointer on the rows that have something underneath them.
 */
export default apiInitializer((api) => {
  api.renderInOutlet("after-sidebar-sections", IngenicSidebarFlyout);
});
