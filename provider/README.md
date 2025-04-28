这个文档介绍了如何开发一个 Terraform Provider。
官方教程如下：https://developer.hashicorp.com/terraform/tutorials/providers-plugin-framework

我们需要了解的概念有：

**什么是 Provider** ？TF Provider 就是 Terraform 的 Plugin，它是以二进制的方式存在的，**但是也是运行在客户端本地的**
。Terraform Client 与 Terraform Provider 之间通过 RPC 通信。Provider 内部代码提供了对 Application Server（或者说云服务的
API）的调用。
![image-20240622102221326](http://127.0.0.1/yandongxiao/typera/main/imgimage-20240622102221326.png?token=AB466OEMWRRFIPHZPD7GO3TGOY2Z6)

**Terraform 如何安装一个 Provider？** Terraform installs providers and verifies their versions and checksums when you run
terraform init. Terraform will download your providers from either the provider registry or a local registry. However,
while building your provider you will want to test Terraform configuration against a local development build of the
provider. The development build will not have an associated version number or an official set of checksums listed in a
provider registry.

Terraform allows you to use local provider builds by setting a dev_overrides block in a configuration file called
`.terraformrc`. This block overrides all other configured installation methods.

Terraform searches for the `.terraformrc` file in your home directory and applies any configuration settings you set.

```shell
# 这是 trafform provider 的安装目录，注意你不能使用 go run 的方式来运行 provider，它是由 TF 来管理和启动的
go env GOBIN

# in ~/.terraformrc
provider_installation {

  dev_overrides {
      "hashicorp.com/edu/hashicups" = "<PATH>"
  }

  # For all other providers, install them directly from their origin provider
  # registries as normal. If you omit this, Terraform will _only_ use
  # the dev_overrides block, and so no other providers will be available.
  direct {}
}
```

**什么是 Provider Client？** Provider Server 说的是在客户端运行的Server进程, 对 Terraform 提供 RPC 服务。Provider Client 是
Provider 代码中生成的访问 Application Server 的 Client 代码。Provider Client 是在 Provider Server 中运行的。问题在于，如果
Application 要求 New Client 时，需要提供一些参数，比如 Hostname, Username, Password 等等。我们在 Terraform 插件中该如何实现？

**什么是 Terraform state？** 以 Data Source 为例，The data source uses the Read method to refresh the Terraform state
based on the schema data. The hashicups_coffees data source will use the configured HashiCups client to call the
HashiCups API coffee listing endpoint and save this data to the Terraform state.

# Implement a provider with the Terraform Plugin Framework

https://developer.hashicorp.com/terraform/tutorials/providers-plugin-framework/providers-plugin-framework-provider#providers-plugin-framework-provider

## Set up your development environment

这里需要注意 Provider 的命名规则，一般是：terraform-provider-hashicups。这既是你的 Provider 名称，也是项目的名称，也是 go
module名称的结尾。这样，在 go install 的时候，会生成一个 terraform-provider-hashicups 的二进制。在 main.tf 中引用该 Provider
的方式如下：

```shell
provider "hashicups" {}
```

> 注意，这个是一个约定俗称，provider 的类型名称之所以叫 hashicups, 是因为我们在实现 Provider 的时候，给它起了一个名字叫
> hashicups。参见 Metadata 方法。

例子中，直接将 go module 的名称也命名为了 `terraform-provider-hashicups`

```shell
go mod edit -module terraform-provider-hashicups
```

## Implement initial provider type

Providers use an implementation of the provider.Provider interface type as the starting point for all implementation
details.

1. A `Metadata` method to define the provider type name for inclusion in each data source and resource type name. For
   example, a resource type named "hashicups_order" would have a provider type name of "hashicups".
   ```golang
   // Metadata returns the provider type name.
   func (p *hashicupsProvider) Metadata(_ context.Context, _ provider.MetadataRequest, resp *provider.MetadataResponse) {
      resp.TypeName = "hashicups"
      resp.Version = p.version
   }
   ```
2. A `Schema` method to define the schema for `provider-level` configuration. Later in these tutorials, you will update
   this method to accept a HashiCups API token and endpoint.
   ```text
   // Schema defines the provider-level schema for configuration data.
   func (p *hashicupsProvider) Schema(_ context.Context, _ provider.SchemaRequest, resp *provider.SchemaResponse) {
       resp.Schema = schema.Schema{
           Attributes: map[string]schema.Attribute{
               "host": schema.StringAttribute{
                   Optional: true,
               },
               "username": schema.StringAttribute{
                   Optional: true,
               },
               "password": schema.StringAttribute{
                   Optional:  true,
                   Sensitive: true,
               },
           },
       }
   }
   ```
   对应的配置如下：
   ```text
   provider "hashicups" {
      host     = "http://localhost:19090"
      username = "education"
      password = "test123"
   }
   ```
3. A Configure method to configure shared clients for data source and resource implementations.
   更进一步的解释可以参见代码注释：Configure is called at the beginning of the provider lifecycle, when
   Terraform sends to the provider the values the user specified in the provider configuration block(这里说的就是
   provider "hashicups" {}). These are supplied in the ConfigureProviderRequest argument. Values from provider
   configuration are often used to initialise an API client, which should be stored on the struct implementing the
   Provider interface. 它的目的是返回一个 API Client！
4. A DataSources method to define the provider's data sources. 比如：
   ```text
   func NewCoffeesDataSource() datasource.DataSource {
       return &coffeesDataSource{}
   }

   type coffeesDataSource struct{}

   func (d *coffeesDataSource) Metadata(_ context.Context, req datasource.MetadataRequest, resp *datasource.MetadataResponse) {
       resp.TypeName = req.ProviderTypeName + "_coffees"
   }

   func (d *coffeesDataSource) Schema(_ context.Context, _ datasource.SchemaRequest, resp *datasource.SchemaResponse) {
       resp.Schema = schema.Schema{}
   }

   func (d *coffeesDataSource) Read(ctx context.Context, req datasource.ReadRequest, resp *datasource.ReadResponse) {
   }
   ```
   这样一来，你就可以在 main.tf 中引用该数据源了：
   ```text
   data "hashicups_coffees" "example" {}
   ```
5. A Resources method to define the provider's resources. 同理，这里是实现 `resource.Resource` 的增删改查的接口。

## Implement the provider server

Terraform providers are server processes that Terraform interacts with to handle each data source and resource
operation. 我们需要明确 TF Provider 就是 Terraform 的 Plugin，它是以二进制的方式存在的，注意也是运行在本地的。Terraform
Client 与 Terraform Provider 之间通过 RPC 通信。Provider 内部代码提供了对 Application Server（或者说云服务的 API）的调用。

```terraform
# in ~/.terraformrc
provider_installation {

  dev_overrides {
    "hashicorp.com/edu/hashicups" = "<PATH>"
  }

  # For all other providers, install them directly from their origin provider
  # registries as normal. If you omit this, Terraform will _only_ use
  # the dev_overrides block, and so no other providers will be available.
  direct {}
}

# in main.tf
terraform {
  required_providers {
    # 由于我们在 ~/.terraformrc 中配置了 dev_overrides，所以会查找一个名为 terraform-provider-hashicups 的二进制
    hashicups = {
      source = "hashicorp.com/edu/hashicups"
    }
  }
}

provider "hashicups" {}

data "hashicups_coffees" "example" {}
```

# Configure provider client

https://developer.hashicorp.com/terraform/tutorials/providers-plugin-framework/providers-plugin-framework-provider-configure#providers-plugin-framework-provider-configure

**什么是 Provider Schema？**

```terraform
provider "hashicups" {
  host     = "http://localhost:19090"
  username = "education"
  password = "test123"
}
```

**什么是 Define the provider data model?** This models the provider schema as a Go type so the data is accessible for
other Go code. 说白了，就是将 main.tf 中 Provider Block 的配置，转换到一个 Go 结构体中。比如：

```text
// hashicupsProviderModel maps provider schema data to a Go type.
type hashicupsProviderModel struct {
	Host     types.String `tfsdk:"host"`
	Username types.String `tfsdk:"username"`
	Password types.String `tfsdk:"password"`
}

# This reads the Terraform configuration using the data model or checks environment variables if data is missing from 
# the configuration. It raises errors if any necessary client configuration is missing. The configured client is then
# created and made available for data sources and resources.
func (p *hashicupsProvider) Configure(ctx context.Context, req provider.ConfigureRequest, resp *provider.ConfigureResponse) {
   // Retrieve provider data from configuration
   var config hashicupsProviderModel
   diags := req.Config.Get(ctx, &config)
   ...
   // Make the HashiCups client available during DataSource and Resource
   // type Configure methods.
   resp.DataSourceData = client
   resp.ResourceData = client
}
```

## Start HashiCups locally

这里说的 HashiCups 指的是例子中的 Application 服务。因为 Terraform Provider 要创建一个访问 Application 服务的 Client.

```bash
cd docker_compose
docker-compose up
```

docker compose file 的内容如下：

```yaml
version: '3.7'
services:
  api:
    image: "hashicorpdemoapp/product-api:v0.0.22"
    ports:
      - "19090:9090"
    volumes:
      - ./conf.json:/config/config.json
    environment:
      CONFIG_FILE: '/config/config.json'
    depends_on:
      - db
  db:
    image: "hashicorpdemoapp/product-api-db:v0.0.22"
    ports:
      - "15432:5432"
    environment:
      POSTGRES_DB: 'products'
      POSTGRES_USER: 'postgres'
      POSTGRES_PASSWORD: 'password'
```

## Implement temporary data source

**Provider configuration only occurs if there is a valid data source or resource supported by the provider and used in a
Terraform configuration.** 所以，为了在 Provider 中真正地使用 Provider 的配置，创建一个Application Client，我们需要实现一个临时的数据源。

注册一个数据源，代码如下：

```text
// internal/provider/provider.go
// DataSources defines the data sources implemented in the provider.
func (p *hashicupsProvider) DataSources(_ context.Context) []func() datasource.DataSource {
    return []func() datasource.DataSource {
        NewCoffeesDataSource,
    }
}


# internal/provider/coffees_data_source.go
package provider

import (
    "context"

    "github.com/hashicorp/terraform-plugin-framework/datasource"
    "github.com/hashicorp/terraform-plugin-framework/datasource/schema"
)

func NewCoffeesDataSource() datasource.DataSource {
    return &coffeesDataSource{}
}

type coffeesDataSource struct{}

func (d *coffeesDataSource) Metadata(_ context.Context, req datasource.MetadataRequest, resp *datasource.MetadataResponse) {
    resp.TypeName = req.ProviderTypeName + "_coffees"
}

func (d *coffeesDataSource) Schema(_ context.Context, _ datasource.SchemaRequest, resp *datasource.SchemaResponse) {
    resp.Schema = schema.Schema{}
}

func (d *coffeesDataSource) Read(ctx context.Context, req datasource.ReadRequest, resp *datasource.ReadResponse) {
}
```

## Verify provider configuration

```bash
HASHICUPS_HOST=http://localhost:19090 \
  HASHICUPS_USERNAME=education \
  HASHICUPS_PASSWORD=test123 \
  terraform plan
```

或者是更新 provider block 如下：

```terraform
terraform {
  required_providers {
    hashicups = {
      source = "hashicorp.com/edu/hashicups"
    }
  }
}

provider "hashicups" {
  host     = "http://localhost:19090"
  username = "education"
  password = "test123"
}

data "hashicups_coffees" "edu" {}
```

Terraform will authenticate with your HashiCups instance using the values from the provider block and once again report
that it is able to read from the hashicups_coffees.example data source. 结果如下：

```bash
$ terraform plan
##...
data.hashicups_coffees.edu: Reading...
data.hashicups_coffees.edu: Read complete after 0s
##...
```

# Implement data source

**什么是 data source type？** 其实就是前面介绍的注册一个 DataSource 的方法。其中：

```text
// Metadata returns the data source type name.
func (d *coffeesDataSource) Metadata(_ context.Context, req datasource.MetadataRequest, resp *datasource.MetadataResponse) {
    resp.TypeName = req.ProviderTypeName + "_coffees"
}
```

说明了 Data Source Type 就等价于一个 Data Source。我们在 main.tf 中定义的应该叫做 Data Source Instance。

```text
data "hashicups_coffees" "example" {}
```

## Implement data source client functionality

注意本小节的标题。

Data sources use the optional Configure method to fetch configured clients from the provider. The provider configures
the HashiCups client and the data source can save a reference to that client for its operations.

```text
type coffeesDataSource struct {
	client *hashicups.Client
}

// Ensure the implementation satisfies the expected interfaces.
var (
	_ datasource.DataSource              = &coffeesDataSource{}
	// 额外增加了这个实现
	_ datasource.DataSourceWithConfigure = &coffeesDataSource{}
)

// Configure adds the provider configured client to the data source.
func (d *coffeesDataSource) Configure(_ context.Context, req datasource.ConfigureRequest, resp *datasource.ConfigureResponse) {
	// Add a nil check when handling ProviderData because Terraform
	// sets that data after it calls the ConfigureProvider RPC.
	if req.ProviderData == nil {
		return
	}

	client, ok := req.ProviderData.(*hashicups.Client)
	if !ok {
		resp.Diagnostics.AddError(
			"Unexpected Data Source Configure Type",
			fmt.Sprintf("Expected *hashicups.Client, got: %T. Please report this issue to the provider developers.", req.ProviderData),
		)

		return
	}

	d.client = client
}

```

## Implement data source schema

**是否实现对 Application 的调用即可？**

The data source uses the Read method to refresh the Terraform state based on the schema data. The hashicups_coffees data
source will use the configured HashiCups client to call the HashiCups API coffee listing endpoint and save this data to
the Terraform state.

The read method follows these steps:

1. Reads coffees list. The method invokes the API client's GetCoffees method.
2. Maps response body to schema attributes. After the method reads the coffees, it maps the []hashicups.Coffee response
   to coffeesModel so the data source can set the Terraform state.
3. Sets state with coffees list.

说白了，就是要将调用 Application 的结果，转换成一个 Go 结构体，然后将这个结构体的内容，设置到 Terraform 的状态中。比如：

```text
diags := resp.State.Set(ctx, &state)
resp.Diagnostics.Append(diags...)
if resp.Diagnostics.HasError() {
    return
}
```

## Implement resource create and read

In this tutorial, you will add create and read capabilities to a new order resource of a provider that interacts with
the API of a fictional coffee-shop application called Hashicups.

## Implement resource update

In this tutorial, you will add update capabilities to the order resource of a provider that interacts with the API of a
fictional coffee-shop application called Hashicups.

# Implement resource import

**什么是 terraform import command?** Terraform 的 import 命令用于将已有基础设施资源纳入 Terraform 的管理，使其能被
Terraform 的状态文件（terraform.tfstate）跟踪。 This import method takes the given order ID from the terraform import
command and enables Terraform to begin managing
the existing order.

```text
// The method will use the resource.ImportStatePassthroughID() function to retrieve the ID value from the terraform 
// import command and save it to the id attribute.
func (r *orderResource) ImportState(ctx context.Context, req resource.ImportStateRequest, resp *resource.ImportStateResponse) {
    // Retrieve import ID and save to id attribute
    resource.ImportStatePassthroughID(ctx, path.Root("id"), req, resp)
}
```

If there are no errors, Terraform will automatically call the resource's Read method to import the rest of the Terraform
state. Since the id attribute is all that is necessary for the Read method to work, no additional implementation is
required.

验证 import 功能的方法：

```bash
terraform apply -auto-approve

terraform show # 会展示 resource "hashicups_order" "edu" 资源

terraform state rm hashicups_order.edu # 只是移除对该资源的管理，资源仍然是存在的。

terraform show # 没有对 resource "hashicups_order" "edu" 进行管理，但是 Output 中可能还有一些信息，会有一点理解上的干扰

curl -X GET -H "Authorization: ${HASHICUPS_TOKEN}" localhost:19090/orders/2 # 验证到该 order id 在 Application 中还是存在的

terraform import hashicups_order.edu 2 # 将该资源重新纳入 Terraform 的管理
```

# Implement a function

**什么是 Function？** Provider-defined functions allow provider developers to define functions that encapsulate offline,
computational logic. Practitioners can call functions from their Terraform configuration. Unlike resources and data
sources, functions do not manage infrastructure or retrieve data from APIs.
> Provider-defined functions do all of their work locally. You should never call remote APIs from within the Run(实现该
> Function 的方法) method.

```text
// Ensure the implementation satisfies the expected interfaces.
var (
    _ provider.Provider              = &hashicupsProvider{}
    _ provider.ProviderWithFunctions = &hashicupsProvider{}
)

func (p *hashicupsProvider) Functions(_ context.Context) []func() function.Function {
    return []func() function.Function{
        NewComputeTaxFunction,
    }
}

package provider

import (
    "context"
    "github.com/hashicorp/terraform-plugin-framework/function"
    "math"
)

// Ensure the implementation satisfies the desired interfaces.
var _ function.Function = &ComputeTaxFunction{}

type ComputeTaxFunction struct{}

func NewComputeTaxFunction() function.Function {
    return &ComputeTaxFunction{}
}

func (f *ComputeTaxFunction) Metadata(ctx context.Context, req function.MetadataRequest, resp *function.MetadataResponse) {
    resp.Name = "compute_tax"
}

func (f *ComputeTaxFunction) Definition(ctx context.Context, req function.DefinitionRequest, resp *function.DefinitionResponse) {
    resp.Definition = function.Definition{
        Summary:     "Compute tax for coffee",
        Description: "Given a price and tax rate, return the total cost including tax.",
        Parameters: []function.Parameter{
            function.Float64Parameter{
                Name:        "price",
                Description: "Price of coffee item.",
            },
            function.Float64Parameter{
                Name:        "rate",
                Description: "Tax rate. 0.085 == 8.5%",
            },
        },
        Return: function.Float64Return{},
    }
}

func (f *ComputeTaxFunction) Run(ctx context.Context, req function.RunRequest, resp *function.RunResponse) {
    var price float64
    var rate float64
    var total float64

    // Read Terraform argument data into the variables
    resp.Error = function.ConcatFuncErrors(resp.Error, req.Arguments.Get(ctx, &price, &rate))

    total = math.Round((price+price*rate)*100) / 100

    // Set the result
    resp.Error = function.ConcatFuncErrors(resp.Error, resp.Result.Set(ctx, total))
}
```

**如何使用该 Function？**

```text
terraform {
  required_providers {
    hashicups = {
      source = "hashicorp.com/edu/hashicups"
    }
  }
  required_version = ">= 1.8.0"
}

provider "hashicups" {
  username = "education"
  password = "test123"
  host     = "http://localhost:19090"
}

output "total_price" {
  value = provider::hashicups::compute_tax(5.00, 0.085)
}
```

plan 的时候直接计算出结果：

```text
Changes to Outputs:
  + total_price = 5.43
```

# Implement automated testing

https://developer.hashicorp.com/terraform/tutorials/providers-plugin-framework/providers-plugin-framework-acceptance-testing

什么是 ACC（Acceptance Testing） 测试？ The terraform-plugin-testing Go module helper/resource package enables providers to
implement automated acceptance testing. The testing framework is built on top of standard go test command functionality
and calls actual Terraform commands, such as terraform apply, terraform import, and terraform destroy. Unlike manual
testing, you do not have to locally reinstall the provider on code updates or switch directories to use the expected
Terraform configuration when you run the automated tests.

测试的重点：

1. **Data source** acceptance testing verifies that the Terraform state contains data after being read from the API.
2. **Resource acceptance testing** verifies that the entire resource lifecycle, such as the Create, Read, Update, and
   Delete
   functionality, along with import capabilities. The testing framework automatically handles destroying test resources
   and returning any errors as a final step, regardless of whether there is a destroy step explicitly written.
3. Function acceptance testing verifies that the function works as expected. Since provider functions require Terraform
   1.8 or newer, the example code checks the version of Terraform before it runs the tests.

# Implement documentation generation

https://developer.hashicorp.com/terraform/tutorials/providers-plugin-framework/providers-plugin-framework-documentation-generation

The terraform-plugin-docs Go module cmd/tfplugindocs command enables providers to implement documentation generation.
The generation uses schema descriptions and conventionally placed files to produce provider documentation that is
compatible with the Terraform Registry.

The `tfplugindocs` tool will automatically include Terraform configuration examples. 所以，你需要准备好 examples, 方便让
tfplugindocs 生成文档。

```text
Provider: examples/provider/provider.tf
Resources: examples/resources/TYPE/resource.tf
Data Sources: examples/data-sources/TYPE/data-source.tf
Functions: examples/functions/TYPE/function.tf
Import: examples/resources/hashicups_order/import.sh
```



10. 如何测试？
4. 如何生成文档？
5. 如何 Public Provider 到 Terraform Registry?
6. 版本概念在哪里体现？

Terratest 是做什么用的？
如何使用该 Provider？
什么是 terraformer https://github.com/GoogleCloudPlatform/terraformer？

