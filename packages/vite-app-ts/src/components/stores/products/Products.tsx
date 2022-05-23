import { Button, Card, Col, message, Row } from 'antd';
import { useEthersContext } from 'eth-hooks/context';
import React, { FC, useCallback } from 'react';

import merchantMock from './mockedMerchants.json';
import productMock from './mockedProducts.json';

import { useAppContracts } from '~~/config/contractContext';

const ProductCard: FC<any> = ({ product, merchant }) => {
  const ethersContext = useEthersContext();
  const mapOfCrypto = useAppContracts('MapOfCrypto', ethersContext.chainId);

  const initiateBuy: any = async () => {
    const key = 'updatable';
    await message.loading({ content: 'Waiting for acceptance...', key });
    try {
      const res = await mapOfCrypto?.makePurchaseRequest(merchant.id, product.id);
      await message.success({
        content: (
          <a
            target="_blank"
            title="Transaction hash"
            href={`https://kovan.etherscan.io/tx/${res?.hash}`}
            rel="noreferrer"
          />
        ),
        duration: 5,
        key,
      });
    } catch (err: any) {
      console.error(err);
      await message.error({ content: err.message, duration: 3, key });
    }
  };

  return (
    <Card
      cover={<img alt="example" src="https://picsum.photos/300/300" />}
      hoverable
      title={product.name}
      actions={[<div>{`Price: ${product.price}${product.currency}`}</div>, <Button onClick={initiateBuy}>Buy</Button>]}>
      <div>{product.description}</div>
    </Card>
  );
};

const Products: FC = () => {
  const { products } = productMock;

  const renderProducts = useCallback(() => {
    const { merchants } = merchantMock;
    const getMerchant = (merchantId) => merchants.find((m) => m.id === merchantId);
    return products.map((product) => (
      <Col key={`${product.id}`} span={6}>
        <ProductCard product={product} merchant={getMerchant(product.merchant)} />
      </Col>
    ));
  }, [products]);

  return (
    <div>
      <div>Products</div>
      <Row gutter={[16, 16]}>{renderProducts()}</Row>
      {/* <div>{JSON.stringify(products)}</div> */}
    </div>
  );
};

export default Products;
