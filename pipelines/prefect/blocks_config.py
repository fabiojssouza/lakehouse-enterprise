"""
Configuração de Blocos Prefect para Lakehouse Enterprise
Configura conexões com Airbyte e DBT
"""

from prefect_airbyte import AirbyteConnection
from prefect_dbt import DbtCoreOperation
from prefect.blocks.system import Secret
import os


def create_airbyte_connections():
    """Cria blocos de conexão Airbyte"""
    
    # Configuração base do Airbyte
    airbyte_server_host = "airbyte-server.airbyte.svc.cluster.local"
    airbyte_server_port = 8001
    
    # Facebook Ads Connection
    facebook_connection = AirbyteConnection(
        connection_id="facebook-ads-connection",
        airbyte_server_host=airbyte_server_host,
        airbyte_server_port=airbyte_server_port,
        airbyte_api_version="v1"
    )
    facebook_connection.save("facebook-ads-connection", overwrite=True)
    
    # Google Ads Connection  
    google_connection = AirbyteConnection(
        connection_id="google-ads-connection",
        airbyte_server_host=airbyte_server_host,
        airbyte_server_port=airbyte_server_port,
        airbyte_api_version="v1"
    )
    google_connection.save("google-ads-connection", overwrite=True)
    
    # ActiveCampaign Connection
    activecampaign_connection = AirbyteConnection(
        connection_id="activecampaign-connection", 
        airbyte_server_host=airbyte_server_host,
        airbyte_server_port=airbyte_server_port,
        airbyte_api_version="v1"
    )
    activecampaign_connection.save("activecampaign-connection", overwrite=True)
    
    print("✅ Blocos Airbyte criados com sucesso")


def create_dbt_blocks():
    """Cria blocos DBT"""
    
    # DBT Core Operation
    dbt_operation = DbtCoreOperation(
        commands=["dbt --version"],  # Comando padrão
        project_dir="/opt/prefect/dbt",
        profiles_dir="/opt/prefect/dbt"
    )
    dbt_operation.save("dbt-lakehouse", overwrite=True)
    
    print("✅ Blocos DBT criados com sucesso")


def create_secrets():
    """Cria secrets necessários"""
    
    # Facebook Ads API
    facebook_token = Secret(value=os.getenv("FACEBOOK_ACCESS_TOKEN", "your_token_here"))
    facebook_token.save("facebook-access-token", overwrite=True)
    
    # Google Ads API
    google_token = Secret(value=os.getenv("GOOGLE_ADS_DEVELOPER_TOKEN", "your_token_here"))
    google_token.save("google-ads-developer-token", overwrite=True)
    
    # ActiveCampaign API
    activecampaign_key = Secret(value=os.getenv("ACTIVECAMPAIGN_API_KEY", "your_key_here"))
    activecampaign_key.save("activecampaign-api-key", overwrite=True)
    
    activecampaign_url = Secret(value=os.getenv("ACTIVECAMPAIGN_API_URL", "https://yourcompany.api-us1.com"))
    activecampaign_url.save("activecampaign-api-url", overwrite=True)
    
    print("✅ Secrets criados com sucesso")


def setup_all_blocks():
    """Configura todos os blocos necessários"""
    print("🔧 Configurando blocos Prefect...")
    
    create_airbyte_connections()
    create_dbt_blocks()
    create_secrets()
    
    print("🎉 Todos os blocos configurados com sucesso!")
    print("\n📋 Próximos passos:")
    print("1. Configure as variáveis de ambiente com suas credenciais")
    print("2. Execute os flows de orquestração")
    print("3. Configure os schedules no Prefect UI")


if __name__ == "__main__":
    setup_all_blocks()

