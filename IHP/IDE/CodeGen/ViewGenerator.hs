module IHP.IDE.CodeGen.ViewGenerator (buildPlan) where

import IHP.Prelude
import IHP.HaskellSupport
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import IHP.ViewSupport
import qualified System.Process as Process
import IHP.IDE.CodeGen.Types
import qualified IHP.IDE.SchemaDesigner.Parser as SchemaDesigner
import IHP.IDE.SchemaDesigner.Types
import qualified Text.Countable as Countable
import IHP.IDE.CodeGen.ControllerGenerator (fieldsForTable)

data ViewConfig = ViewConfig
    { controllerName :: Text 
    , applicationName :: Text
    , modelName :: Text
    , viewName :: Text
    } deriving (Eq, Show)

buildPlan :: Text -> Text -> Text -> IO (Either Text [GeneratorAction])
buildPlan viewName applicationName controllerName =
    if (null viewName || null controllerName)
        then pure $ Left "View name and controller name cannot be empty"
        else do 
            schema <- SchemaDesigner.parseSchemaSql >>= \case
                Left parserError -> pure []
                Right statements -> pure statements
            let modelName = tableNameToModelName controllerName
            let viewConfig = ViewConfig {controllerName, applicationName, modelName, viewName }
            pure $ Right $ generateGenericView schema viewConfig

-- E.g. qualifiedViewModuleName config "Edit" == "Web.View.Users.Edit"
qualifiedViewModuleName :: ViewConfig -> Text -> Text
qualifiedViewModuleName config viewName =
    get #applicationName config <> ".View." <> get #controllerName config <> "." <> viewName

generateGenericView :: [Statement] -> ViewConfig -> [GeneratorAction]
generateGenericView schema config = 
        let 
            controllerName = get #controllerName config
            name = get #viewName config
            singularName = config |> get #modelName
            singularVariableName = lcfirst singularName
            pluralVariableName = lcfirst controllerName
            nameWithSuffix = if "View" `isSuffixOf` name
                then name
                else name <> "View" --e.g. "TestView"

            indexAction = Countable.pluralize singularName <> "Action"
            specialCases = [
                  ("IndexView", indexView)
                , ("ShowView", showView)
                , ("EditView", editView)
                , ("NewView", newView)
                ]

            modelFields :: [Text]
            modelFields = fieldsForTable schema pluralVariableName


            viewHeader =
                ""
                <> "module " <> qualifiedViewModuleName config name <> " where\n"
                <> "import " <> get #applicationName config <> ".View.Prelude\n"
                <> "\n"
            
            genericView = 
                viewHeader
                <> "data " <> nameWithSuffix <> " = " <> nameWithSuffix <> "\n"
                <> "\n"
                <> "instance View " <> nameWithSuffix <> " ViewContext where\n"
                <> "    html " <> nameWithSuffix <> " { .. } = [hsx|\n"
                <> "        <nav>\n"
                <> "            <ol class=\"breadcrumb\">\n"
                <> "                <li class=\"breadcrumb-item\"><a href={" <> indexAction <> "}>" <> Countable.pluralize name <> "</a></li>\n"
                <> "                <li class=\"breadcrumb-item active\">" <> nameWithSuffix <> "</li>\n"
                <> "            </ol>\n"
                <> "        </nav>\n"
                <> "        <h1>" <> nameWithSuffix <> "</h1>\n"
                <> "    |]\n"

            showView = 
                viewHeader
                <> "data ShowView = ShowView { " <> singularVariableName <> " :: " <> singularName <> " }\n"
                <> "\n"
                <> "instance View ShowView ViewContext where\n"
                <> "    html ShowView { .. } = [hsx|\n"
                <> "        <nav>\n"
                <> "            <ol class=\"breadcrumb\">\n"
                <> "                <li class=\"breadcrumb-item\"><a href={" <> indexAction <> "}>" <> Countable.pluralize name <> "</a></li>\n"
                <> "                <li class=\"breadcrumb-item active\">Show " <> singularName <> "</li>\n"
                <> "            </ol>\n"
                <> "        </nav>\n"
                <> "        <h1>Show " <> singularName <> "</h1>\n"
                <> "    |]\n"

            newView = 
                viewHeader
                <> "data NewView = NewView { " <> singularVariableName <> " :: " <> singularName <> " }\n"
                <> "\n"
                <> "instance View NewView ViewContext where\n"
                <> "    html NewView { .. } = [hsx|\n"
                <> "        <nav>\n"
                <> "            <ol class=\"breadcrumb\">\n"
                <> "                <li class=\"breadcrumb-item\"><a href={" <> indexAction <> "}>" <> Countable.pluralize name <> "</a></li>\n"
                <> "                <li class=\"breadcrumb-item active\">Edit " <> singularName <> "</li>\n"
                <> "            </ol>\n"
                <> "        </nav>\n"
                <> "        <h1>New " <> singularName <> "</h1>\n"
                <> "        {renderForm " <> singularVariableName <> "}\n"
                <> "    |]\n"
                <> "\n"
                <> "renderForm :: " <> singularName <> " -> Html\n"
                <> "renderForm " <> singularVariableName <> " = formFor " <> singularVariableName <> " [hsx|\n"
                <> (intercalate "\n" (map (\field -> "    {textField #" <> field <> "}") modelFields)) <> "\n"
                <> "    {submitButton}\n"
                <> "|]\n"

            editView = 
                viewHeader
                <> "data EditView = EditView { " <> singularVariableName <> " :: " <> singularName <> " }\n"
                <> "\n"
                <> "instance View EditView ViewContext where\n"
                <> "    html EditView { .. } = [hsx|\n"
                <> "        <nav>\n"
                <> "            <ol class=\"breadcrumb\">\n"
                <> "                <li class=\"breadcrumb-item\"><a href={" <> indexAction <> "}>" <> Countable.pluralize name <> "</a></li>\n"
                <> "                <li class=\"breadcrumb-item active\">Edit " <> singularName <> "</li>\n"
                <> "            </ol>\n"
                <> "        </nav>\n"
                <> "        <h1>Edit " <> singularName <> "</h1>\n"
                <> "        {renderForm " <> singularVariableName <> "}\n"
                <> "    |]\n"
                <> "\n"
                <> "renderForm :: " <> singularName <> " -> Html\n"
                <> "renderForm " <> singularVariableName <> " = formFor " <> singularVariableName <> " [hsx|\n"
                <> (intercalate "\n" (map (\field -> "    {textField #" <> field <> "}") modelFields)) <> "\n"
                <> "    {submitButton}\n"
                <> "|]\n"

            indexView = 
                viewHeader
                <> "data IndexView = IndexView { " <> pluralVariableName <> " :: [" <> singularName <> "] }\n"
                <> "\n"
                <> "instance View IndexView ViewContext where\n"
                <> "    html IndexView { .. } = [hsx|\n"
                <> "        <nav>\n"
                <> "            <ol class=\"breadcrumb\">\n"
                <> "                <li class=\"breadcrumb-item active\"><a href={" <> indexAction <> "}>" <> Countable.pluralize name <> "</a></li>\n"
                <> "            </ol>\n"
                <> "        </nav>\n"
                <> "        <h1>" <> name <> " <a href={pathTo New" <> singularName <> "Action} class=\"btn btn-primary ml-4\">+ New</a></h1>\n"
                <> "        <table class=\"table table-responsive\">\n"
                <> "            <thead>\n"
                <> "                <tr>\n"
                <> "                    <th>" <> singularName <> "</th>\n"
                <> "                    <th></th>\n"
                <> "                </tr>\n"
                <> "            </thead>\n"
                <> "            <tbody>{forEach " <> pluralVariableName <> " render" <> singularName <> "}</tbody>\n"
                <> "        </table>\n"
                <> "    |]\n"
                <> "\n\n"
                <> "render" <> singularName <> " " <> singularVariableName <> " = [hsx|\n"
                <> "    <tr>\n"
                <> "        <td>{" <> singularVariableName <> "}</td>\n"
                <> "        <td><a href={Show" <> singularName <> "Action (get #id " <> singularVariableName <> ")}>Show</a></td>\n"
                <> "        <td><a href={Edit" <> singularName <> "Action (get #id " <> singularVariableName <> ")} class=\"text-muted\">Edit</a></td>\n"
                <> "        <td><a href={Delete" <> singularName <> "Action (get #id " <> singularVariableName <> ")} class=\"js-delete text-muted\">Delete</a></td>\n"
                <> "    </tr>\n"
                <> "|]\n"
            chosenView = fromMaybe genericView (lookup nameWithSuffix specialCases)
        in
            [ EnsureDirectory { directory = get #applicationName config <> "/View/" <> controllerName }
            , CreateFile { filePath = get #applicationName config <> "/View/" <> controllerName <> "/" <> name <> ".hs", fileContent = chosenView }
            , AddImport { filePath = get #applicationName config <> "/Controller/" <> controllerName <> ".hs", fileContent = "import " <> qualifiedViewModuleName config name }
            ]